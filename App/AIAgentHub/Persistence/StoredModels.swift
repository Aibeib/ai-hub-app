import Foundation
import SwiftData
import AIAgentHubCore

@Model
final class StoredModelConfig {
    @Attribute(.unique) var id: UUID
    var name: String
    var providerRawValue: String
    var modelName: String
    var baseURLString: String?
    var temperature: Double
    var maxTokens: Int
    var isDefault: Bool
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(record: ModelConfigRecord) {
        id = record.id
        apply(record)
    }

    func apply(_ record: ModelConfigRecord) {
        name = record.name
        providerRawValue = record.provider.rawValue
        modelName = record.modelName
        baseURLString = record.baseURL?.absoluteString
        temperature = record.temperature
        maxTokens = record.maxTokens
        isDefault = record.isDefault
        isEnabled = record.isEnabled
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    var record: ModelConfigRecord {
        ModelConfigRecord(
            id: id,
            name: name,
            provider: ModelProvider(rawValue: providerRawValue) ?? .openai,
            modelName: modelName,
            baseURL: baseURLString.flatMap(URL.init(string:)),
            temperature: temperature,
            maxTokens: maxTokens,
            isDefault: isDefault,
            isEnabled: isEnabled,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

@Model
final class StoredChatSession {
    @Attribute(.unique) var id: UUID
    var title: String
    var modelConfigId: UUID?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var isPinned: Bool
    var isDeleted: Bool
    var deleteExpireAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \StoredChatMessage.session) var messages: [StoredChatMessage]

    init(record: ChatSessionRecord) {
        id = record.id
        apply(record)
        messages = []
    }

    func apply(_ record: ChatSessionRecord) {
        title = record.title
        modelConfigId = record.modelConfigId
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        isArchived = record.isArchived
        isPinned = record.isPinned
        isDeleted = record.isDeleted
        deleteExpireAt = record.deleteExpireAt
    }

    var record: ChatSessionRecord {
        ChatSessionRecord(
            id: id,
            title: title,
            modelConfigId: modelConfigId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isArchived: isArchived,
            isPinned: isPinned,
            isDeleted: isDeleted,
            deleteExpireAt: deleteExpireAt
        )
    }
}

@Model
final class StoredChatMessage {
    @Attribute(.unique) var id: UUID
    var roleRawValue: String
    var content: String
    var timestamp: Date
    var isStreaming: Bool
    var errorMessage: String?
    var session: StoredChatSession?

    init(message: ChatMessageDTO, isStreaming: Bool = false, errorMessage: String? = nil) {
        id = message.id
        roleRawValue = message.role.rawValue
        content = message.content
        timestamp = message.timestamp
        self.isStreaming = isStreaming
        self.errorMessage = errorMessage
    }

    var dto: ChatMessageDTO {
        ChatMessageDTO(
            id: id,
            role: MessageRole(rawValue: roleRawValue) ?? .assistant,
            content: content,
            timestamp: timestamp
        )
    }
}

@Model
final class StoredToolExecutionLog {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID
    var toolName: String
    var riskLevelRawValue: String
    var decisionRawValue: String
    var summary: String
    var createdAt: Date
    var expiresAt: Date

    init(entry: ToolExecutionLogEntry) {
        id = entry.id
        apply(entry)
    }

    func apply(_ entry: ToolExecutionLogEntry) {
        sessionId = entry.sessionId
        toolName = entry.toolName
        riskLevelRawValue = entry.riskLevel.rawValue
        decisionRawValue = entry.decision.rawValue
        summary = entry.summary
        createdAt = entry.createdAt
        expiresAt = entry.expiresAt
    }

    var entry: ToolExecutionLogEntry {
        ToolExecutionLogEntry(
            id: id,
            sessionId: sessionId,
            toolName: toolName,
            riskLevel: ToolRiskLevel(rawValue: riskLevelRawValue) ?? .low,
            decision: ToolAuthorizationDecision(rawValue: decisionRawValue) ?? .cancelled,
            summary: summary,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }
}

@Model
final class StoredBoundDevice {
    @Attribute(.unique) var id: UUID
    var name: String
    var host: String
    var port: Int
    var kindRawValue: String
    var pairedAt: Date
    var lastSeenAt: Date?

    init(device: BoundDevice) {
        id = device.id
        apply(device)
    }

    func apply(_ device: BoundDevice) {
        name = device.name
        host = device.host
        port = device.port
        kindRawValue = device.kind.rawValue
        pairedAt = device.pairedAt
        lastSeenAt = device.lastSeenAt
    }

    var device: BoundDevice {
        BoundDevice(
            id: id,
            name: name,
            host: host,
            port: port,
            kind: DeviceKind(rawValue: kindRawValue) ?? .unknown,
            pairedAt: pairedAt,
            lastSeenAt: lastSeenAt
        )
    }
}

