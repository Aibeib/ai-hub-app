import Foundation

public protocol AIService: Sendable {
    func streamChat(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

public struct ContextBuilder: Sendable {
    private let maxCharacters: Int

    public init(maxCharacters: Int = 24_000) {
        self.maxCharacters = maxCharacters
    }

    /// Build the messages sent to the model.
    ///
    /// Strategy (turn-aware):
    /// - Walk the conversation from newest to oldest, accumulating `user/assistant/tool` turns
    ///   as logical units. A "turn" is a user message plus the consecutive assistant/tool
    ///   replies that follow it. We keep whole turns rather than slicing mid-reply so the
    ///   model never sees a half-answer.
    /// - System messages (set per-session via setSessionSystemPrompt) are *always* kept,
    ///   regardless of budget — they're how the user steers the model.
    /// - The most recent turn is also always kept, even if it alone exceeds the budget. The
    ///   alternative is sending nothing, which is worse than sending one large turn.
    public func build(from messages: [ChatMessageDTO]) -> [ChatMessageDTO] {
        // Separate system messages so they don't compete with conversation turns for budget.
        let systemMessages = messages.filter { $0.role == .system }
        let conversation = messages
            .filter { $0.role != .system }
            .sorted { $0.timestamp < $1.timestamp }

        guard !conversation.isEmpty else {
            return systemMessages
        }

        // Group into turns: each turn starts at a user message (or the first message if there's
        // no user at the head) and extends through the following non-user messages.
        var turns: [[ChatMessageDTO]] = []
        var current: [ChatMessageDTO] = []
        for message in conversation {
            if message.role == .user && !current.isEmpty {
                turns.append(current)
                current = [message]
            } else {
                current.append(message)
            }
        }
        if !current.isEmpty {
            turns.append(current)
        }

        // Walk newest → oldest, always include the most recent turn even if oversized.
        var selected: [[ChatMessageDTO]] = []
        var consumed = 0
        for (index, turn) in turns.enumerated().reversed() {
            let turnSize = turn.reduce(0) { $0 + $1.content.count }
            if index == turns.count - 1 {
                // Newest turn — keep whole no matter what.
                selected.insert(turn, at: 0)
                consumed += turnSize
                continue
            }
            if consumed + turnSize <= maxCharacters {
                selected.insert(turn, at: 0)
                consumed += turnSize
            } else {
                break
            }
        }

        return systemMessages + selected.flatMap { $0 }
    }
}

public enum ChatOrchestratorError: Error, Equatable {
    /// User has disabled third-party API calls in privacy preferences, and the chosen model is
    /// not the on-device Apple provider.
    case thirdPartyDisabled(provider: ModelProvider)
    /// Regenerate was requested but there's no prior user message to replay.
    case noUserMessageToReplay
}

public final class ChatOrchestrator: @unchecked Sendable {
    private let repository: any ChatRepository
    private let aiService: any AIService
    private let redactor: PrivacyRedactor
    private let contextBuilder: ContextBuilder
    private let toolRegistry: ToolRegistry?
    private let privacyPreferences: PrivacyPreferences
    private let titleDeriver: SessionTitleDeriver

    public init(
        repository: any ChatRepository,
        aiService: any AIService,
        redactor: PrivacyRedactor = PrivacyRedactor(),
        contextBuilder: ContextBuilder = ContextBuilder(),
        toolRegistry: ToolRegistry? = nil,
        privacyPreferences: PrivacyPreferences = .default,
        titleDeriver: SessionTitleDeriver = SessionTitleDeriver()
    ) {
        self.repository = repository
        self.aiService = aiService
        self.redactor = redactor
        self.contextBuilder = contextBuilder
        self.toolRegistry = toolRegistry
        self.privacyPreferences = privacyPreferences
        self.titleDeriver = titleDeriver
    }

    @discardableResult
    @MainActor
    public func sendUserMessage(
        _ text: String,
        in sessionId: UUID,
        using model: ResolvedModelConfig,
        tools: [ToolDefinition] = [],
        preferredResponseLanguage: String? = nil
    ) async throws -> String {
        try await sendUserMessage(
            text,
            in: sessionId,
            using: model,
            tools: tools,
            streamingBuffer: nil,
            onUserMessagePersisted: nil,
            preferredResponseLanguage: preferredResponseLanguage
        )
    }

    /// Streaming variant: tokens are pushed into `streamingBuffer` as they arrive. The final
    /// assistant message is still appended to the repository when the stream finishes.
    ///
    /// `@MainActor` is mandatory: the production repository is SwiftData-backed, and SwiftData's
    /// main `ModelContext` is not thread-safe. Without this annotation the for-await loop body
    /// (which calls `repository.appendMessage(...)`, `repository.recordTokenUsage(...)`, etc.)
    /// resumes on the cooperative global pool per SE-0338 and crashes the moment the provider
    /// streams its first SSE chunk back. The repository protocol can't be `@MainActor` because
    /// the in-memory test implementation is plain `Sendable`; isolating the orchestrator itself
    /// is the surgical fix.
    @discardableResult
    @MainActor
    public func sendUserMessage(
        _ text: String,
        in sessionId: UUID,
        using model: ResolvedModelConfig,
        tools: [ToolDefinition] = [],
        streamingBuffer: StreamingResponseBuffer? = nil,
        onUserMessagePersisted: (@MainActor @Sendable () -> Void)? = nil,
        preferredResponseLanguage: String? = nil
    ) async throws -> String {
        // Privacy gate: third-party providers may be globally disabled. On-device Apple models
        // bypass this check since the text never leaves the device.
        if model.provider != .apple, !privacyPreferences.allowThirdPartyAPIs {
            if let streamingBuffer {
                await streamingBuffer.fail("Third-party API calls are disabled in Privacy settings.")
            }
            throw ChatOrchestratorError.thirdPartyDisabled(provider: model.provider)
        }

        // Privacy gate: the user can opt out of pre-send redaction. When opted out we still
        // record the *original* message in local storage — the toggle only controls what is
        // sent to the provider, not what we keep locally.
        let outboundText: String
        if privacyPreferences.redactBeforeSending {
            outboundText = redactor.redact(text)
        } else {
            outboundText = text
        }

        // Auto-title: if this is the first user message in the session and the session still
        // has a default-ish title, derive a short title from the message. We derive from the
        // *original* text (not the redacted one) so titles read naturally.
        let existing = repository.messages(for: sessionId)
        let isFirstUserMessage = !existing.contains { $0.role == .user }
        if isFirstUserMessage,
           let session = repository.session(id: sessionId),
           shouldAutoRename(currentTitle: session.title) {
            let derived = titleDeriver.derive(from: text)
            if derived != session.title {
                repository.renameSession(sessionId, title: derived)
            }
        }

        repository.appendMessage(
            ChatMessageDTO(role: .user, content: outboundText),
            to: sessionId
        )
        onUserMessagePersisted?()

        let context = contextBuilder.build(from: repository.messages(for: sessionId))
        var requestMessages = context
        // Prepend the session's system prompt, if any. Stored separately from the message log
        // so the user can re-edit it later without touching the conversation.
        let userSystemPrompt = repository.session(id: sessionId)?
            .systemPrompt?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Always inject a baseline system message describing tool availability. Without this
        // the model commonly replies "I can't access the internet" even though `web_fetch` is
        // registered — the user only sees the empty-handed answer, not the tool catalog.
        // We compose it with the user-supplied prompt (if any) rather than choose one over
        // the other, so user steering still wins on tone/role.
        let toolHint = Self.toolAvailabilityHint(
            for: tools,
            preferredLanguage: preferredResponseLanguage
        )
        let combinedSystem: String?
        switch (userSystemPrompt, toolHint) {
        case let (.some(user), .some(hint)) where !user.isEmpty:
            combinedSystem = "\(user)\n\n\(hint)"
        case let (.some(user), nil) where !user.isEmpty:
            combinedSystem = user
        case let (_, .some(hint)):
            combinedSystem = hint
        default:
            combinedSystem = nil
        }
        if let combinedSystem {
            requestMessages.insert(
                ChatMessageDTO(role: .system, content: combinedSystem, timestamp: Date(timeIntervalSince1970: 0)),
                at: 0
            )
        }
        let request = ChatRequest(
            model: model,
            messages: requestMessages,
            tools: tools,
            temperature: model.temperature,
            maxTokens: model.maxTokens
        )

        var response = ""
        do {
            for try await event in aiService.streamChat(request: request) {
                try Task.checkCancellation()
                switch event {
                case let .token(token):
                    response += token
                    if let streamingBuffer {
                        await streamingBuffer.append(token: token)
                    }
                case let .toolCall(toolCall):
                    if let streamingBuffer {
                        await streamingBuffer.record(toolCall: toolCall)
                    }
                    guard let toolRegistry else {
                        continue
                    }
                    let arguments = try ToolArgumentDecoder.decode(toolCall.argumentsJSON)
                    let result = try await toolRegistry.execute(
                        toolName: toolCall.name,
                        arguments: arguments,
                        sessionId: sessionId
                    )
                    repository.appendMessage(
                        ChatMessageDTO(role: .tool, content: result.displayText),
                        to: sessionId
                    )
                case let .usage(usage):
                    if let streamingBuffer {
                        await streamingBuffer.record(usage: usage)
                    }
                    repository.recordTokenUsage(usage, for: sessionId)
                case let .stop(reason):
                    if let streamingBuffer {
                        await streamingBuffer.record(stopReason: reason)
                    }
                case .completed:
                    break
                }
            }
        } catch is CancellationError {
            if let streamingBuffer {
                await streamingBuffer.fail("Generation cancelled.")
            }
            // Persist what we got so far so the partial reply isn't lost.
            if !response.isEmpty {
                repository.appendMessage(
                    ChatMessageDTO(role: .assistant, content: response),
                    to: sessionId
                )
            }
            throw CancellationError()
        } catch {
            if let streamingBuffer {
                await streamingBuffer.fail(error.localizedDescription)
            }
            throw error
        }

        repository.appendMessage(
            ChatMessageDTO(role: .assistant, content: response),
            to: sessionId
        )
        if let streamingBuffer {
            await streamingBuffer.complete()
        }
        return response
    }

    /// Heuristic for whether the current title was a placeholder that we should overwrite.
    /// We avoid renaming sessions whose title looks like it was set deliberately by the user.
    private func shouldAutoRename(currentTitle: String) -> Bool {
        let trimmed = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty
            || trimmed == "new chat"
            || trimmed == "new conversation"
            || trimmed == "untitled"
            || trimmed == "新建对话"
            || trimmed == "未命名"
            || trimmed.hasPrefix("chat ")
    }

    /// Compose a short system message that tells the model which tools it has. Without this
    /// nudge several providers (DeepSeek in particular) reply "I have no internet access"
    /// even though `web_fetch` is in the tools array — they only consult tools when something
    /// in the conversation hints at their existence.
    ///
    /// We also embed today's date so trivia like "what day is it?" doesn't trigger an
    /// unnecessary `web_fetch` call with empty/invented arguments.
    ///
    /// `preferredLanguage` is an ISO-639 short code (e.g. "zh", "en"). When supplied we
    /// add a one-line instruction telling the model to write its final answer AND its
    /// chain-of-thought in that language. The UI passes the current language so a Chinese
    /// user gets a Chinese "推理过程" instead of an English thinking dump they can't read.
    static func toolAvailabilityHint(
        for tools: [ToolDefinition],
        now: Date = Date(),
        preferredLanguage: String? = nil
    ) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dateLine = "Today's date is \(formatter.string(from: now)) (UTC). Use this for any \"what day is it / what's the date / current year\" questions instead of calling tools."

        let languageLine: String?
        switch preferredLanguage?.lowercased() {
        case "zh", "zh-hans", "zh-cn":
            languageLine = "请用简体中文回答用户，包括你的推理 / 思考过程（reasoning_content / <think>）也使用中文，除非用户明确要求其他语言。"
        case "en", "en-us":
            languageLine = "Reply in English by default, including the reasoning / thinking block, unless the user explicitly asks for another language."
        case .none:
            languageLine = nil
        default:
            // Generic instruction for any other language code — emits a soft hint without
            // hard-coding a translation that might be inaccurate.
            languageLine = "Reply in the user's UI language (\(preferredLanguage ?? "auto-detect")), including the reasoning / thinking block, unless the user explicitly asks otherwise."
        }

        var lines: [String] = [dateLine]
        if let languageLine {
            lines.append(languageLine)
        }
        if !tools.isEmpty {
            let toolList = tools.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
            lines.append("""
                You have access to the following tools. Prefer calling them over refusing or claiming you cannot reach the internet. Only call a tool when its arguments can be filled with real values (e.g. don't call web_fetch without a concrete http(s) URL):
                \(toolList)
                """)
        }
        return lines.joined(separator: "\n\n")
    }

    /// Regenerate the most recent assistant message. Drops the trailing assistant (and tool)
    /// turns, then re-sends to the model using the *prior* user message as the trigger.
    ///
    /// Returns the new assistant content. Throws if there's no user message to replay.
    @discardableResult
    @MainActor
    public func regenerateLastAssistantMessage(
        in sessionId: UUID,
        using model: ResolvedModelConfig,
        tools: [ToolDefinition] = [],
        streamingBuffer: StreamingResponseBuffer? = nil,
        preferredResponseLanguage: String? = nil
    ) async throws -> String {
        let messages = repository.messages(for: sessionId)

        // Walk from the end, dropping trailing assistant/tool turns until we hit a user message.
        var lastUserMessage: ChatMessageDTO?
        for message in messages.reversed() {
            if message.role == .user {
                lastUserMessage = message
                break
            }
            repository.deleteMessage(message.id, in: sessionId)
        }
        // Also drop the last user message itself — sendUserMessage will re-append it.
        guard let userMessage = lastUserMessage else {
            throw ChatOrchestratorError.noUserMessageToReplay
        }
        repository.deleteMessage(userMessage.id, in: sessionId)

        return try await sendUserMessage(
            userMessage.content,
            in: sessionId,
            using: model,
            tools: tools,
            streamingBuffer: streamingBuffer,
            onUserMessagePersisted: nil,
            preferredResponseLanguage: preferredResponseLanguage
        )
    }
}

public struct StubAIService: AIService {
    private let events: [ChatStreamEvent]
    private let error: Error?

    public init(events: [ChatStreamEvent], error: Error? = nil) {
        self.events = events
        self.error = error
    }

    public func streamChat(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }

            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}
