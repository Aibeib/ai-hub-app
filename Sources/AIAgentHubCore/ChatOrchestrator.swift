import Foundation

public protocol AIService: Sendable {
    func streamChat(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

public struct ContextBuilder: Sendable {
    private let maxCharacters: Int

    public init(maxCharacters: Int = 24_000) {
        self.maxCharacters = maxCharacters
    }

    public func build(from messages: [ChatMessageDTO]) -> [ChatMessageDTO] {
        var remaining = maxCharacters
        var selected: [ChatMessageDTO] = []

        for message in messages.reversed() {
            guard remaining > 0 else {
                break
            }

            if message.content.count <= remaining {
                selected.append(message)
                remaining -= message.content.count
            }
        }

        return selected.reversed()
    }
}

public final class ChatOrchestrator: @unchecked Sendable {
    private let repository: any ChatRepository
    private let aiService: any AIService
    private let redactor: PrivacyRedactor
    private let contextBuilder: ContextBuilder
    private let toolRegistry: ToolRegistry?

    public init(
        repository: any ChatRepository,
        aiService: any AIService,
        redactor: PrivacyRedactor = PrivacyRedactor(),
        contextBuilder: ContextBuilder = ContextBuilder(),
        toolRegistry: ToolRegistry? = nil
    ) {
        self.repository = repository
        self.aiService = aiService
        self.redactor = redactor
        self.contextBuilder = contextBuilder
        self.toolRegistry = toolRegistry
    }

    @discardableResult
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
    @discardableResult
    public func sendUserMessage(
        _ text: String,
        in sessionId: UUID,
        using model: ResolvedModelConfig,
        tools: [ToolDefinition] = [],
        streamingBuffer: StreamingResponseBuffer?
    ) async throws -> String {
        let redacted = redactor.redact(text)
        repository.appendMessage(
            ChatMessageDTO(role: .user, content: redacted),
            to: sessionId
        )

        let context = contextBuilder.build(from: repository.messages(for: sessionId))
        let request = ChatRequest(
            model: model,
            messages: context,
            tools: tools,
            temperature: model.temperature,
            maxTokens: model.maxTokens
        )

        var response = ""
        do {
            for try await event in aiService.streamChat(request: request) {
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
                case .completed:
                    break
                }
            }
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
