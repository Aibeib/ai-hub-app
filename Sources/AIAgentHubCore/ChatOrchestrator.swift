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

    public init(
        repository: any ChatRepository,
        aiService: any AIService,
        redactor: PrivacyRedactor = PrivacyRedactor(),
        contextBuilder: ContextBuilder = ContextBuilder()
    ) {
        self.repository = repository
        self.aiService = aiService
        self.redactor = redactor
        self.contextBuilder = contextBuilder
    }

    @discardableResult
    public func sendUserMessage(
        _ text: String,
        in sessionId: UUID,
        using model: ResolvedModelConfig,
        tools: [ToolDefinition] = []
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
        for try await event in aiService.streamChat(request: request) {
            switch event {
            case let .token(token):
                response += token
            case .toolCall:
                continue
            case .usage:
                continue
            case .completed:
                break
            }
        }

        repository.appendMessage(
            ChatMessageDTO(role: .assistant, content: response),
            to: sessionId
        )
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

