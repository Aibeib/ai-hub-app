import Foundation

public enum ModelProvider: String, Codable, CaseIterable, Sendable {
    case openai
    case deepseek
    case anthropic
    case apple

    public var displayName: String {
        switch self {
        case .openai:
            "OpenAI"
        case .deepseek:
            "DeepSeek"
        case .anthropic:
            "Claude"
        case .apple:
            "Apple Foundation Models"
        }
    }

    public var defaultBaseURL: URL? {
        switch self {
        case .openai:
            URL(string: "https://api.openai.com/v1/chat/completions")
        case .deepseek:
            URL(string: "https://api.deepseek.com/chat/completions")
        case .anthropic:
            URL(string: "https://api.anthropic.com/v1/messages")
        case .apple:
            nil
        }
    }
}

public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case tool
}

public struct ModelConfigRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var provider: ModelProvider
    public var modelName: String
    public var baseURL: URL?
    public var temperature: Double
    public var maxTokens: Int
    public var isDefault: Bool
    public var isEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        provider: ModelProvider,
        modelName: String,
        baseURL: URL? = nil,
        temperature: Double = 0.7,
        maxTokens: Int = 4_096,
        isDefault: Bool = false,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.modelName = modelName
        self.baseURL = baseURL
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.isDefault = isDefault
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ResolvedModelConfig: Equatable, Sendable {
    public var id: UUID
    public var provider: ModelProvider
    public var name: String
    public var modelName: String
    public var endpoint: URL?
    public var apiKey: String?
    public var temperature: Double
    public var maxTokens: Int

    public init(
        id: UUID,
        provider: ModelProvider,
        name: String,
        modelName: String,
        endpoint: URL?,
        apiKey: String?,
        temperature: Double,
        maxTokens: Int
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.modelName = modelName
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public struct ChatMessageDTO: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var role: MessageRole
    public var content: String
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

public struct ChatRequest: Sendable {
    public var model: ResolvedModelConfig
    public var messages: [ChatMessageDTO]
    public var tools: [ToolDefinition]
    public var temperature: Double
    public var maxTokens: Int

    public init(
        model: ResolvedModelConfig,
        messages: [ChatMessageDTO],
        tools: [ToolDefinition] = [],
        temperature: Double,
        maxTokens: Int
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public struct TokenUsage: Codable, Equatable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int

    public init(promptTokens: Int, completionTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

public enum ChatStreamEvent: Equatable, Sendable {
    case token(String)
    case toolCall(ToolCallRequest)
    case usage(TokenUsage)
    case stop(StopReason)
    case completed
}

/// Why the assistant stream stopped. Both OpenAI's `finish_reason` and Claude's `stop_reason`
/// fold into this single enum.
public enum StopReason: String, Codable, Equatable, Sendable {
    case endTurn         // natural completion
    case maxTokens       // hit max_tokens / token budget
    case toolUse         // model wants to call a tool, more turns follow
    case stopSequence    // matched a configured stop string
    case contentFilter   // provider blocked output
    case other

    public var displayLabel: String {
        switch self {
        case .endTurn: "Complete"
        case .maxTokens: "Truncated (max tokens)"
        case .toolUse: "Awaiting tool result"
        case .stopSequence: "Stop sequence"
        case .contentFilter: "Filtered by provider"
        case .other: "Stopped"
        }
    }

    public var isTruncation: Bool {
        switch self {
        case .maxTokens, .stopSequence, .contentFilter: true
        case .endTurn, .toolUse, .other: false
        }
    }

    /// Map an OpenAI `finish_reason` string into the canonical enum.
    public static func fromOpenAI(_ raw: String?) -> StopReason? {
        switch raw {
        case "stop": .endTurn
        case "length": .maxTokens
        case "tool_calls", "function_call": .toolUse
        case "content_filter": .contentFilter
        case nil: nil
        default: .other
        }
    }

    /// Map a Claude `stop_reason` string into the canonical enum.
    public static func fromClaude(_ raw: String?) -> StopReason? {
        switch raw {
        case "end_turn": .endTurn
        case "max_tokens": .maxTokens
        case "tool_use": .toolUse
        case "stop_sequence": .stopSequence
        case nil: nil
        default: .other
        }
    }
}

public struct ToolCallRequest: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public struct ChatSessionRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var modelConfigId: UUID?
    public var systemPrompt: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var isArchived: Bool
    public var isPinned: Bool
    public var isDeleted: Bool
    public var deleteExpireAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        modelConfigId: UUID? = nil,
        systemPrompt: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        isPinned: Bool = false,
        isDeleted: Bool = false,
        deleteExpireAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.modelConfigId = modelConfigId
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.isPinned = isPinned
        self.isDeleted = isDeleted
        self.deleteExpireAt = deleteExpireAt
    }
}

