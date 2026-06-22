import Foundation

/// User-controllable privacy preferences that persist across launches.
///
/// These are *not* secrets — they describe behaviour toggles (e.g., whether to call third-party
/// APIs, whether to discover devices on the local network). Stored separately from API keys so
/// they can live in plain UserDefaults rather than the Keychain.
public struct PrivacyPreferences: Codable, Equatable, Sendable {
    public var allowThirdPartyAPIs: Bool
    public var enableLocalNetworkDiscovery: Bool
    public var redactBeforeSending: Bool
    public var retainAuditLogsDays: Int

    public init(
        allowThirdPartyAPIs: Bool = true,
        enableLocalNetworkDiscovery: Bool = false,
        redactBeforeSending: Bool = true,
        retainAuditLogsDays: Int = 30
    ) {
        self.allowThirdPartyAPIs = allowThirdPartyAPIs
        self.enableLocalNetworkDiscovery = enableLocalNetworkDiscovery
        self.redactBeforeSending = redactBeforeSending
        self.retainAuditLogsDays = retainAuditLogsDays
    }

    public static let `default` = PrivacyPreferences()
}

public protocol PrivacyPreferencesRepository: Sendable {
    func load() -> PrivacyPreferences
    func save(_ preferences: PrivacyPreferences)
}

/// In-memory repository for tests and the no-Xcode validation target.
public final class InMemoryPrivacyPreferencesRepository: PrivacyPreferencesRepository, @unchecked Sendable {
    private var current: PrivacyPreferences
    private let lock = NSLock()

    public init(initial: PrivacyPreferences = .default) {
        self.current = initial
    }

    public func load() -> PrivacyPreferences {
        lock.withLock { current }
    }

    public func save(_ preferences: PrivacyPreferences) {
        lock.withLock { current = preferences }
    }
}

/// UserDefaults-backed repository for the iOS app. Keys are namespaced under
/// `aiagenthub.privacy.*` so they don't collide with anything else.
public final class UserDefaultsPrivacyPreferencesRepository: PrivacyPreferencesRepository, @unchecked Sendable {
    public enum DefaultsKey {
        public static let preferences = "aiagenthub.privacy.preferences"
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = DefaultsKey.preferences) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> PrivacyPreferences {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode(PrivacyPreferences.self, from: data)
        else {
            return .default
        }
        return decoded
    }

    public func save(_ preferences: PrivacyPreferences) {
        guard let encoded = try? JSONEncoder().encode(preferences) else {
            return
        }
        defaults.set(encoded, forKey: key)
    }
}
