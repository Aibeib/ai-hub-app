import Foundation

/// Tracks which session the user had open last so the app can re-select it on relaunch.
///
/// Two implementations: an in-memory variant for tests/headless, and a UserDefaults-backed
/// one for the real app. Both store a single UUID, nothing else.
public protocol LastSessionStore: Sendable {
    func load() -> UUID?
    func save(_ sessionId: UUID?)
}

public final class InMemoryLastSessionStore: LastSessionStore, @unchecked Sendable {
    private var stored: UUID?
    private let lock = NSLock()

    public init(initial: UUID? = nil) {
        self.stored = initial
    }

    public func load() -> UUID? {
        lock.withLock { stored }
    }

    public func save(_ sessionId: UUID?) {
        lock.withLock { stored = sessionId }
    }
}

public final class UserDefaultsLastSessionStore: LastSessionStore, @unchecked Sendable {
    public enum DefaultsKey {
        public static let lastSessionId = "aiagenthub.lastSessionId"
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = DefaultsKey.lastSessionId) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> UUID? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return UUID(uuidString: raw)
    }

    public func save(_ sessionId: UUID?) {
        if let id = sessionId {
            defaults.set(id.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
