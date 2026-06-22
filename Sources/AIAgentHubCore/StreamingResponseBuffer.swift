import Foundation

/// Streaming buffer for assistant responses. The orchestrator pushes tokens here as they arrive
/// so the UI layer can observe partial text instead of waiting for the full reply.
///
/// Designed to be safe for concurrent producer/consumer access. The producer is the orchestrator
/// running on a background task; the consumer is the UI thread observing `currentText`.
public actor StreamingResponseBuffer {
    public private(set) var currentText: String = ""
    public private(set) var toolCalls: [ToolCallRequest] = []
    public private(set) var usage: TokenUsage?
    public private(set) var isCompleted: Bool = false
    public private(set) var failure: String?

    private var continuations: [UUID: AsyncStream<StreamingSnapshot>.Continuation] = [:]

    public init() {}

    public struct StreamingSnapshot: Sendable, Equatable {
        public let text: String
        public let toolCalls: [ToolCallRequest]
        public let usage: TokenUsage?
        public let isCompleted: Bool
        public let failure: String?

        public init(
            text: String,
            toolCalls: [ToolCallRequest],
            usage: TokenUsage?,
            isCompleted: Bool,
            failure: String?
        ) {
            self.text = text
            self.toolCalls = toolCalls
            self.usage = usage
            self.isCompleted = isCompleted
            self.failure = failure
        }
    }

    public func append(token: String) {
        currentText += token
        broadcast()
    }

    public func record(toolCall: ToolCallRequest) {
        toolCalls.append(toolCall)
        broadcast()
    }

    public func record(usage: TokenUsage) {
        self.usage = usage
        broadcast()
    }

    public func complete() {
        isCompleted = true
        broadcast()
        finishStreams()
    }

    public func fail(_ message: String) {
        failure = message
        isCompleted = true
        broadcast()
        finishStreams()
    }

    public func snapshot() -> StreamingSnapshot {
        StreamingSnapshot(
            text: currentText,
            toolCalls: toolCalls,
            usage: usage,
            isCompleted: isCompleted,
            failure: failure
        )
    }

    /// Subscribe to incremental snapshots. The returned stream finishes when `complete()` or
    /// `fail(_:)` is called.
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
    }
}
