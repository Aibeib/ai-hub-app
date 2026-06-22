import Foundation

public enum SecretStoreError: Error, Equatable {
    case invalidKey
}

public protocol SecretStore: Sendable {
    func save(_ value: String, for key: String) throws
    func read(_ key: String) throws -> String?
    func delete(_ key: String) throws
}

public final class KeyValueSecretStore: SecretStore, @unchecked Sendable {
    private var values: [String: String]
    private let lock = NSLock()

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public func save(_ value: String, for key: String) throws {
        guard !key.isEmpty else {
            throw SecretStoreError.invalidKey
        }
        lock.withLock {
            values[key] = value
        }
    }

    public func read(_ key: String) throws -> String? {
        guard !key.isEmpty else {
            throw SecretStoreError.invalidKey
        }
        return lock.withLock {
            values[key]
        }
    }

    public func delete(_ key: String) throws {
        guard !key.isEmpty else {
            throw SecretStoreError.invalidKey
        }
        _ = lock.withLock {
            values.removeValue(forKey: key)
        }
    }
}

public struct APIKeyResolver: Sendable {
    private let secretStore: any SecretStore

    public init(secretStore: any SecretStore) {
        self.secretStore = secretStore
    }

    public func resolve(_ model: ModelConfigRecord) throws -> ResolvedModelConfig {
        let key = secretKey(for: model)
        return ResolvedModelConfig(
            id: model.id,
            provider: model.provider,
            name: model.name,
            modelName: model.modelName,
            endpoint: model.baseURL ?? model.provider.defaultBaseURL,
            apiKey: try secretStore.read(key),
            temperature: model.temperature,
            maxTokens: model.maxTokens
        )
    }

    public func secretKey(for model: ModelConfigRecord) -> String {
        "model.\(model.id.uuidString).apiKey"
    }
}
