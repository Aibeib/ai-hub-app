import Foundation

public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public var now: Date { Date() }

    public init() {}
}

public struct FixedClock: Clock {
    public var now: Date

    public init(now: Date) {
        self.now = now
    }
}

public enum ChatRepositoryError: Error, Equatable {
    case sessionNotFound(UUID)
}

public protocol ChatRepository: Sendable {
    @discardableResult
    func createSession(title: String, modelConfigId: UUID?) -> ChatSessionRecord
    func sessions(includeDeleted: Bool) -> [ChatSessionRecord]
    func session(id: UUID) -> ChatSessionRecord?
    @discardableResult
    func appendMessage(_ message: ChatMessageDTO, to sessionId: UUID) -> ChatMessageDTO
    func messages(for sessionId: UUID) -> [ChatMessageDTO]
    func renameSession(_ sessionId: UUID, title: String)
    func archiveSession(_ sessionId: UUID)
    func softDeleteSession(_ sessionId: UUID)
    func restoreSession(_ sessionId: UUID)
    func setSessionModel(_ sessionId: UUID, modelConfigId: UUID?)
    func setSessionPinned(_ sessionId: UUID, isPinned: Bool)
    func purgeExpiredDeletedSessions()
    func clearAllSessions()
}

public final class InMemoryChatRepository: ChatRepository, @unchecked Sendable {
    private var sessionStorage: [UUID: ChatSessionRecord] = [:]
    private var messageStorage: [UUID: [ChatMessageDTO]] = [:]
    private let clock: any Clock
    private let lock = NSLock()

    public init(clock: any Clock = SystemClock()) {
        self.clock = clock
    }

    @discardableResult
    public func createSession(title: String, modelConfigId: UUID?) -> ChatSessionRecord {
        lock.withLock {
            let session = ChatSessionRecord(
                title: title,
                modelConfigId: modelConfigId,
                createdAt: clock.now,
                updatedAt: clock.now
            )
            sessionStorage[session.id] = session
            messageStorage[session.id] = []
            return session
        }
    }

    public func sessions(includeDeleted: Bool = false) -> [ChatSessionRecord] {
        lock.withLock {
            sessionStorage.values
                .filter { includeDeleted || !$0.isDeleted }
                .sorted { lhs, rhs in
                    if lhs.isPinned != rhs.isPinned {
                        return lhs.isPinned
                    }
                    return lhs.updatedAt > rhs.updatedAt
                }
        }
    }

    public func session(id: UUID) -> ChatSessionRecord? {
        lock.withLock {
            sessionStorage[id]
        }
    }

    @discardableResult
    public func appendMessage(_ message: ChatMessageDTO, to sessionId: UUID) -> ChatMessageDTO {
        lock.withLock {
            var stored = message
            if stored.timestamp == Date.distantPast {
                stored.timestamp = clock.now
            }
            messageStorage[sessionId, default: []].append(stored)
            if var session = sessionStorage[sessionId] {
                session.updatedAt = clock.now
                sessionStorage[sessionId] = session
            }
            return stored
        }
    }

    public func messages(for sessionId: UUID) -> [ChatMessageDTO] {
        lock.withLock {
            messageStorage[sessionId, default: []].sorted { $0.timestamp < $1.timestamp }
        }
    }

    public func renameSession(_ sessionId: UUID, title: String) {
        lock.withLock {
            guard var session = sessionStorage[sessionId] else {
                return
            }
            session.title = title
            session.updatedAt = clock.now
            sessionStorage[sessionId] = session
        }
    }

    public func archiveSession(_ sessionId: UUID) {
        lock.withLock {
            guard var session = sessionStorage[sessionId] else {
                return
            }
            session.isArchived = true
            session.updatedAt = clock.now
            sessionStorage[sessionId] = session
        }
    }

    public func softDeleteSession(_ sessionId: UUID) {
        lock.withLock {
            guard var session = sessionStorage[sessionId] else {
                return
            }
            session.isDeleted = true
            session.deleteExpireAt = clock.now.addingTimeInterval(7 * 24 * 60 * 60)
            session.updatedAt = clock.now
            sessionStorage[sessionId] = session
        }
    }

    public func restoreSession(_ sessionId: UUID) {
        lock.withLock {
            guard var session = sessionStorage[sessionId] else {
                return
            }
            session.isDeleted = false
            session.deleteExpireAt = nil
            session.updatedAt = clock.now
            sessionStorage[sessionId] = session
        }
    }

    public func setSessionModel(_ sessionId: UUID, modelConfigId: UUID?) {
        lock.withLock {
            guard var session = sessionStorage[sessionId] else {
                return
            }
            session.modelConfigId = modelConfigId
            session.updatedAt = clock.now
            sessionStorage[sessionId] = session
        }
    }

    public func setSessionPinned(_ sessionId: UUID, isPinned: Bool) {
        lock.withLock {
            guard var session = sessionStorage[sessionId] else {
                return
            }
            session.isPinned = isPinned
            session.updatedAt = clock.now
            sessionStorage[sessionId] = session
        }
    }

    public func purgeExpiredDeletedSessions() {
        lock.withLock {
            let expiredIds = sessionStorage.values
                .filter { session in
                    guard session.isDeleted, let deleteExpireAt = session.deleteExpireAt else {
                        return false
                    }
                    return deleteExpireAt <= clock.now
                }
                .map(\.id)

            for id in expiredIds {
                sessionStorage.removeValue(forKey: id)
                messageStorage.removeValue(forKey: id)
            }
        }
    }

    public func clearAllSessions() {
        lock.withLock {
            sessionStorage.removeAll()
            messageStorage.removeAll()
        }
    }
}

public protocol ModelConfigRepository: Sendable {
    func upsert(_ config: ModelConfigRecord)
    func all(includeDisabled: Bool) -> [ModelConfigRecord]
    func defaultModel() -> ModelConfigRecord?
    func delete(id: UUID)
}

public final class InMemoryModelConfigRepository: ModelConfigRepository, @unchecked Sendable {
    private var storage: [UUID: ModelConfigRecord] = [:]
    private let lock = NSLock()

    public init(configs: [ModelConfigRecord] = []) {
        self.storage = Dictionary(uniqueKeysWithValues: configs.map { ($0.id, $0) })
    }

    public func upsert(_ config: ModelConfigRecord) {
        lock.withLock {
            if config.isDefault {
                for id in storage.keys {
                    storage[id]?.isDefault = false
                }
            }
            storage[config.id] = config
        }
    }

    public func all(includeDisabled: Bool = true) -> [ModelConfigRecord] {
        lock.withLock {
            storage.values
                .filter { includeDisabled || $0.isEnabled }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    public func defaultModel() -> ModelConfigRecord? {
        lock.withLock {
            storage.values.first { $0.isDefault && $0.isEnabled }
                ?? storage.values.first { $0.isEnabled }
        }
    }

    public func delete(id: UUID) {
        _ = lock.withLock {
            storage.removeValue(forKey: id)
        }
    }
}
