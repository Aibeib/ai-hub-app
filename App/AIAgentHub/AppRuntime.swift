import Foundation
import Observation
import AIAgentHubCore

@Observable
final class AppRuntime {
    let chatRepository: InMemoryChatRepository
    let modelRepository: InMemoryModelConfigRepository
    let secretStore: any SecretStore
    let modelManager: ModelConfigurationManager
    var modelConfigs: [ModelConfigRecord]

    init(secretStore: any SecretStore = KeychainSecretStore()) {
        chatRepository = InMemoryChatRepository()
        modelRepository = InMemoryModelConfigRepository()
        self.secretStore = secretStore
        modelManager = ModelConfigurationManager(
            repository: modelRepository,
            secretStore: secretStore
        )
        modelConfigs = []
        seedDefaultsIfNeeded()
    }

    func refreshModels() {
        modelConfigs = modelRepository.all()
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
        guard modelRepository.all().isEmpty else {
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

