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
        tools: [ToolDefinition] = []
    ) async throws -> String {
        try await sendUserMessage(
            text,
            in: sessionId,
            using: model,
            tools: tools,
            streamingBuffer: nil
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
        streamingBuffer: StreamingResponseBuffer?
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

        let context = contextBuilder.build(from: repository.messages(for: sessionId))
        var requestMessages = context
        // Prepend the session's system prompt, if any. Stored separately from the message log
        // so the user can re-edit it later without touching the conversation.
        if let session = repository.session(id: sessionId),
           let prompt = session.systemPrompt,
           !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            requestMessages.insert(
                ChatMessageDTO(role: .system, content: prompt, timestamp: Date(timeIntervalSince1970: 0)),
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
            || trimmed.hasPrefix("chat ")
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
        streamingBuffer: StreamingResponseBuffer? = nil
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
            streamingBuffer: streamingBuffer
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
