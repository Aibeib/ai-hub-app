import Foundation

public struct ModelConfigurationDraft: Equatable, Sendable {
    public var id: UUID?
    public var name: String
    public var provider: ModelProvider
    public var modelName: String
    public var baseURL: URL?
    public var apiKey: String?
    public var temperature: Double
    public var maxTokens: Int
    public var isDefault: Bool
    public var isEnabled: Bool

    public init(
        id: UUID? = nil,
        name: String,
        provider: ModelProvider,
        modelName: String,
        baseURL: URL?,
        apiKey: String?,
        temperature: Double,
        maxTokens: Int,
        isDefault: Bool,
        isEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.modelName = modelName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.isDefault = isDefault
        self.isEnabled = isEnabled
    }
}

public enum ModelConfigurationError: Error, Equatable {
    case emptyName
    case emptyModelName
    case temperatureOutOfRange
    case maxTokensOutOfRange
    case noEnabledModel
    case missingAPIKey(UUID)
}

public final class ModelConfigurationManager: @unchecked Sendable {
    private let repository: InMemoryModelConfigRepository
    private let secretStore: any SecretStore
    private let resolver: APIKeyResolver
    private let clock: any Clock

    public init(
        repository: InMemoryModelConfigRepository,
        secretStore: any SecretStore,
        clock: any Clock = SystemClock()
    ) {
        self.repository = repository
        self.secretStore = secretStore
        self.resolver = APIKeyResolver(secretStore: secretStore)
        self.clock = clock
    }

    @discardableResult
    public func save(_ draft: ModelConfigurationDraft) throws -> ModelConfigRecord {
        try validate(draft)

        let existing = draft.id.flatMap { id in repository.all().first { $0.id == id } }
        let id = draft.id ?? UUID()
        let createdAt = existing?.createdAt ?? clock.now
        let record = ModelConfigRecord(
            id: id,
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            provider: draft.provider,
            modelName: draft.modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: draft.baseURL,
            temperature: draft.temperature,
            maxTokens: draft.maxTokens,
            isDefault: draft.isDefault,
            isEnabled: draft.isEnabled,
            createdAt: createdAt,
            updatedAt: clock.now
        )

        repository.upsert(record)

        if let apiKey = draft.apiKey, !apiKey.isEmpty {
            try secretStore.save(apiKey, for: resolver.secretKey(for: record))
        }

        return record
    }

    public func enabledModels() -> [ModelConfigRecord] {
        repository.all(includeDisabled: false)
    }

    public func defaultModel() -> ModelConfigRecord? {
        repository.defaultModel()
    }

    public func resolveDefaultModel() throws -> ResolvedModelConfig {
        guard let model = repository.defaultModel() else {
            throw ModelConfigurationError.noEnabledModel
        }

        let resolved = try resolver.resolve(model)
        if model.provider != .apple, resolved.apiKey?.isEmpty ?? true {
            throw ModelConfigurationError.missingAPIKey(model.id)
        }
        return resolved
    }

    public func makeServiceForDefault(client: any AIHTTPClient = URLSessionAIHTTPClient()) throws -> any AIService {
        let resolved = try resolveDefaultModel()
        return AIServiceFactory.make(provider: resolved.provider, client: client)
    }

    public func deleteModel(_ id: UUID) throws {
        if let model = repository.all().first(where: { $0.id == id }) {
            try secretStore.delete(resolver.secretKey(for: model))
        }
        repository.delete(id: id)
    }

    private func validate(_ draft: ModelConfigurationDraft) throws {
        if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ModelConfigurationError.emptyName
        }
        if draft.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ModelConfigurationError.emptyModelName
        }
        if !(0...2).contains(draft.temperature) {
            throw ModelConfigurationError.temperatureOutOfRange
        }
        if !(1...200_000).contains(draft.maxTokens) {
            throw ModelConfigurationError.maxTokensOutOfRange
        }
    }
}

