import Foundation
import Observation
import SwiftData
import AIAgentHubCore

@Observable
@MainActor
final class AppRuntime {
    let chatRepository: any ChatRepository
    let modelRepository: any ModelConfigRepository
    let secretStore: any SecretStore
    let modelManager: ModelConfigurationManager
    let auditStore: SwiftDataAuditLogStore?
    let memoryAuditStore: InMemoryAuditLogStore?
    let toolRegistry: ToolRegistry
    var modelConfigs: [ModelConfigRecord]
    var auditEntries: [ToolExecutionLogEntry] {
        auditStore?.entries ?? memoryAuditStore?.entries ?? []
    }

    init(modelContext: ModelContext, secretStore: any SecretStore = KeychainSecretStore()) {
        chatRepository = SwiftDataChatRepository(context: modelContext)
        modelRepository = SwiftDataModelConfigRepository(context: modelContext)
        self.secretStore = secretStore
        let auditStore = SwiftDataAuditLogStore(context: modelContext)
        self.auditStore = auditStore
        memoryAuditStore = nil
        toolRegistry = ToolRegistry(
            tools: [TextSummaryTool()],
            auditStore: auditStore,
            authorization: StaticToolAuthorization(decision: .approved)
        )
        modelManager = ModelConfigurationManager(
            repository: modelRepository,
            secretStore: secretStore
        )
        modelConfigs = []
        seedDefaultsIfNeeded()
    }

    init(secretStore: any SecretStore = KeyValueSecretStore()) {
        chatRepository = InMemoryChatRepository()
        modelRepository = InMemoryModelConfigRepository()
        self.secretStore = secretStore
        auditStore = nil
        let memoryAuditStore = InMemoryAuditLogStore()
        self.memoryAuditStore = memoryAuditStore
        toolRegistry = ToolRegistry(
            tools: [TextSummaryTool()],
            auditStore: memoryAuditStore,
            authorization: StaticToolAuthorization(decision: .approved)
        )
        modelManager = ModelConfigurationManager(
            repository: modelRepository,
            secretStore: secretStore
        )
        modelConfigs = []
        seedDefaultsIfNeeded()
    }

    func refreshModels() {
        modelConfigs = modelRepository.all(includeDisabled: true)
    }

    @discardableResult
    func saveModel(_ draft: ModelConfigurationDraft) throws -> ModelConfigRecord {
        let record = try modelManager.save(draft)
        refreshModels()
        return record
    }

    func deleteModel(_ id: UUID) throws {
        try modelManager.deleteModel(id)
        refreshModels()
    }

    private func seedDefaultsIfNeeded() {
        guard modelRepository.all(includeDisabled: true).isEmpty else {
            refreshModels()
            return
        }

        let defaults = [
            ModelConfigurationDraft(
                name: "OpenAI",
                provider: .openai,
                modelName: "gpt-4.1-mini",
                baseURL: nil,
                apiKey: nil,
                temperature: 0.7,
                maxTokens: 2_048,
                isDefault: true,
                isEnabled: true
            ),
            ModelConfigurationDraft(
                name: "DeepSeek",
                provider: .deepseek,
                modelName: "deepseek-chat",
                baseURL: nil,
                apiKey: nil,
                temperature: 0.7,
                maxTokens: 2_048,
                isDefault: false,
                isEnabled: true
            ),
            ModelConfigurationDraft(
                name: "Claude",
                provider: .anthropic,
                modelName: "claude-sonnet-4-5",
                baseURL: nil,
                apiKey: nil,
                temperature: 0.7,
                maxTokens: 4_096,
                isDefault: false,
                isEnabled: true
            )
        ]

        for draft in defaults {
            _ = try? modelManager.save(draft)
        }
        refreshModels()
    }
}
