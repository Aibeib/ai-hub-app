import Foundation

/// Streaming buffer for assistant responses. The orchestrator pushes tokens here as they
/// arrive so the UI layer can observe partial text instead of waiting for the full reply.
///
/// Designed to be safe for concurrent producer/consumer access. The producer is the
/// orchestrator running on a background task; the consumer is the UI thread observing
/// snapshots.
///
/// ## Typewriter pacing
///
/// Network SSE chunks arrive bursty — DeepSeek and Anthropic both regularly deliver
/// 50–200 characters in a single chunk, which appears in the UI as a single visual
/// "flash" of new text. Major chat apps (ChatGPT, DeepSeek web, Claude.ai) all hide that
/// burstiness by buffering tokens internally and revealing them at a roughly constant
/// rate. We do the same here:
///
/// - `currentText` is the **truth** — everything the model has emitted so far.
/// - `visibleText` is what the UI sees — it advances toward `currentText` at
///   `revealCharactersPerSecond` characters/sec.
/// - A short-lived release `Task` ticks every `tickInterval` and advances `visibleText`
///   one batch at a time. The task auto-suspends when caught up and resumes on the next
///   `append`.
/// - `complete()` and `fail(_:)` reveal any remaining text immediately so the user never
///   waits *after* the model stopped.
///
/// Tunables are stored on the actor rather than as static constants so tests can run
/// with a fast (or instant) reveal speed.
public actor StreamingResponseBuffer {
    /// Everything the model has emitted so far. Tests inspect this directly when they
    /// don't care about typewriter pacing; the UI never reads it.
    public private(set) var currentText: String = ""
    /// Text safe to show in the UI. Always a prefix of `currentText` (in terms of
    /// character count — we work in Swift `Character`s so emoji and CJK don't fragment).
    public private(set) var visibleText: String = ""
    public private(set) var toolCalls: [ToolCallRequest] = []
    public private(set) var usage: TokenUsage?
    public private(set) var stopReason: StopReason?
    public private(set) var isCompleted: Bool = false
    public private(set) var failure: String?

    private var continuations: [UUID: AsyncStream<StreamingSnapshot>.Continuation] = [:]
    private var releaseTask: Task<Void, Never>?

    /// Reveal speed. ~60 chars/sec is the comfortable reading-while-it-types rate the
    /// commercial chat clients converged on. Higher = snappier but flashier; lower =
    /// smoother but laggier when the model is faster than the eye.
    private let revealCharactersPerSecond: Double
    /// How often the ticker wakes up to release more characters. 50 ms gives a roughly
    /// 20 fps reveal which reads fluidly on iOS without burning a CPU core.
    private let tickInterval: TimeInterval
    /// When true, every `append` immediately reveals everything (no pacing). Tests use
    /// this to assert content without sleeping.
    private let instantReveal: Bool

    public init(
        revealCharactersPerSecond: Double = 60,
        tickInterval: TimeInterval = 0.05,
        instantReveal: Bool = false
    ) {
        self.revealCharactersPerSecond = revealCharactersPerSecond
        self.tickInterval = tickInterval
        self.instantReveal = instantReveal
    }

    public struct StreamingSnapshot: Sendable, Equatable {
        public let text: String
        public let toolCalls: [ToolCallRequest]
        public let usage: TokenUsage?
        public let stopReason: StopReason?
        public let isCompleted: Bool
        public let failure: String?

        public init(
            text: String,
            toolCalls: [ToolCallRequest],
            usage: TokenUsage?,
            stopReason: StopReason?,
            isCompleted: Bool,
            failure: String?
        ) {
            self.text = text
            self.toolCalls = toolCalls
            self.usage = usage
            self.stopReason = stopReason
            self.isCompleted = isCompleted
            self.failure = failure
        }
    }

    public func append(token: String) {
        currentText += token
        if instantReveal {
            visibleText = currentText
            broadcast()
            return
        }
        scheduleReleaseTickerIfNeeded()
    }

    public func record(toolCall: ToolCallRequest) {
        toolCalls.append(toolCall)
        broadcast()
    }

    public func record(usage: TokenUsage) {
        self.usage = usage
        broadcast()
    }

    public func record(stopReason: StopReason) {
        self.stopReason = stopReason
        broadcast()
    }

    public func complete() {
        revealAll()
        isCompleted = true
        broadcast()
        finishStreams()
    }

    public func fail(_ message: String) {
        revealAll()
        failure = message
        isCompleted = true
        broadcast()
        finishStreams()
    }

    public func snapshot() -> StreamingSnapshot {
        StreamingSnapshot(
            text: visibleText,
            toolCalls: toolCalls,
            usage: usage,
            stopReason: stopReason,
            isCompleted: isCompleted,
            failure: failure
        )
    }

    /// Subscribe to incremental snapshots. The returned stream finishes when `complete()`
    /// or `fail(_:)` is called.
    public func observe() -> AsyncStream<StreamingSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(snapshot())

            continuation.onTermination = { @Sendable [weak self] _ in
                guard let self else { return }
                Task { await self.removeContinuation(id: id) }
            }

            if isCompleted {
                continuation.finish()
                continuations.removeValue(forKey: id)
            }
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func broadcast() {
        let snap = snapshot()
        for continuation in continuations.values {
            continuation.yield(snap)
        }
    }

    private func finishStreams() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        releaseTask?.cancel()
        releaseTask = nil
    }

    /// Reveal the remaining buffer instantly. Used on completion / failure so the user
    /// doesn't sit watching characters trickle out after the model has already stopped.
    private func revealAll() {
        visibleText = currentText
        releaseTask?.cancel()
        releaseTask = nil
    }

    /// Start (or re-arm) the typewriter ticker if there's pending text to reveal. The
    /// task ends itself when caught up; the next `append` re-arms it.
    private func scheduleReleaseTickerIfNeeded() {
        // If a ticker is already running, it'll see the new content on its next tick —
        // no need to launch another. (Tasks are cheap but more than one would race on
        // visibleText.)
        if releaseTask != nil { return }
        guard visibleText.count < currentText.count else {
            broadcast()
            return
        }

        let charsPerTick = max(1, Int((revealCharactersPerSecond * tickInterval).rounded()))
        let nanosPerTick = UInt64(tickInterval * 1_000_000_000)
        releaseTask = Task { [weak self] in
            // Loop until we run out of buffered text. Each iteration: sleep, advance
            // `visibleText` by up to `charsPerTick` characters, broadcast.
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: nanosPerTick)
                } catch {
                    return
                }
                guard let self else { return }
                let caughtUp = await self.advanceVisible(by: charsPerTick)
                if caughtUp {
                    await self.markReleaseTaskFinished()
                    return
                }
            }
        }
    }

    /// Called by the ticker task when it naturally catches up. This is essential: if we
    /// leave `releaseTask` non-nil after the task returns, the next network append thinks
    /// a ticker is still alive and never starts a new one, so later tokens either stall
    /// or arrive in large bursts. That's the exact opposite of the smooth typewriter
    /// behaviour we want.
    private func markReleaseTaskFinished() {
        releaseTask = nil
        // Race guard: a new append can arrive after the ticker observed "caught up"
        // but before this cleanup runs. If so, immediately re-arm the ticker instead of
        // leaving buffered text stranded.
        if visibleText.count < currentText.count, !isCompleted {
            scheduleReleaseTickerIfNeeded()
        }
    }

    /// Move `visibleText` forward by `n` characters. Returns true when the buffer is
    /// fully drained so the caller knows to stop the ticker.
    private func advanceVisible(by n: Int) -> Bool {
        let currentCount = currentText.count
        let visibleCount = visibleText.count
        guard visibleCount < currentCount else {
            broadcast()
            return true
        }
        let nextCount = min(currentCount, visibleCount + n)
        let endIndex = currentText.index(currentText.startIndex, offsetBy: nextCount)
        visibleText = String(currentText[..<endIndex])
        broadcast()
        if nextCount == currentCount {
            return true
        }
        return false
    }
}
