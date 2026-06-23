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
    func deleteMessage(_ messageId: UUID, in sessionId: UUID)
    func updateMessageContent(_ messageId: UUID, in sessionId: UUID, newContent: String)
    func deleteMessagesAfter(_ messageId: UUID, in sessionId: UUID)
    @discardableResult
    func branchSession(_ sourceSessionId: UUID, upToMessageId: UUID, newTitle: String) -> ChatSessionRecord?
    func renameSession(_ sessionId: UUID, title: String)
    func archiveSession(_ sessionId: UUID)
    func softDeleteSession(_ sessionId: UUID)
    func restoreSession(_ sessionId: UUID)
    func setSessionModel(_ sessionId: UUID, modelConfigId: UUID?)
    func setSessionPinned(_ sessionId: UUID, isPinned: Bool)
    func setSessionSystemPrompt(_ sessionId: UUID, systemPrompt: String?)
    func recordTokenUsage(_ usage: TokenUsage, for sessionId: UUID)
    func tokenUsage(for sessionId: UUID) -> TokenUsage
    func search(query: String, limit: Int) -> [ChatMessageSearchHit]
    func purgeExpiredDeletedSessions()
    func clearAllSessions()
}

/// Result entry for full-text search across all stored messages.
public struct ChatMessageSearchHit: Identifiable, Equatable, Sendable {
    public var id: UUID { message.id }
    public let sessionId: UUID
    public let sessionTitle: String
    public let message: ChatMessageDTO

    public init(sessionId: UUID, sessionTitle: String, message: ChatMessageDTO) {
        self.sessionId = sessionId
        self.sessionTitle = sessionTitle
        self.message = message
    }
}

public final class InMemoryChatRepository: ChatRepository, @unchecked Sendable {
    private var sessionStorage: [UUID: ChatSessionRecord] = [:]
    private var messageStorage: [UUID: [ChatMessageDTO]] = [:]
    private var usageStorage: [UUID: TokenUsage] = [:]
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

    public func setSessionSystemPrompt(_ sessionId: UUID, systemPrompt: String?) {
        lock.withLock {
            guard var session = sessionStorage[sessionId] else {
                return
            }
            // Normalize empty / whitespace-only strings to nil so the orchestrator skips them.
            let trimmed = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            session.systemPrompt = (trimmed?.isEmpty ?? true) ? nil : trimmed
            session.updatedAt = clock.now
            sessionStorage[sessionId] = session
        }
    }

    public func deleteMessage(_ messageId: UUID, in sessionId: UUID) {
        lock.withLock {
            messageStorage[sessionId]?.removeAll { $0.id == messageId }
            if var session = sessionStorage[sessionId] {
                session.updatedAt = clock.now
                sessionStorage[sessionId] = session
            }
        }
    }

    public func updateMessageContent(_ messageId: UUID, in sessionId: UUID, newContent: String) {
        lock.withLock {
            guard var messages = messageStorage[sessionId],
                  let index = messages.firstIndex(where: { $0.id == messageId }) else {
                return
            }
            messages[index].content = newContent
            messageStorage[sessionId] = messages
            if var session = sessionStorage[sessionId] {
                session.updatedAt = clock.now
                sessionStorage[sessionId] = session
            }
        }
    }

    public func deleteMessagesAfter(_ messageId: UUID, in sessionId: UUID) {
        lock.withLock {
            guard var messages = messageStorage[sessionId] else { return }
            messages.sort { $0.timestamp < $1.timestamp }
            guard let cutoff = messages.firstIndex(where: { $0.id == messageId }) else { return }
            let dropAfter = cutoff + 1
            guard dropAfter < messages.count else { return }
            messages.removeSubrange(dropAfter..<messages.count)
            messageStorage[sessionId] = messages
            if var session = sessionStorage[sessionId] {
                session.updatedAt = clock.now
                sessionStorage[sessionId] = session
            }
        }
    }

    @discardableResult
    public func branchSession(_ sourceSessionId: UUID, upToMessageId: UUID, newTitle: String) -> ChatSessionRecord? {
        lock.withLock {
            guard let source = sessionStorage[sourceSessionId],
                  let sourceMessages = messageStorage[sourceSessionId] else {
                return nil
            }

            let sorted = sourceMessages.sorted { $0.timestamp < $1.timestamp }
            guard let cutoff = sorted.firstIndex(where: { $0.id == upToMessageId }) else {
                return nil
            }
            let preserved = Array(sorted.prefix(cutoff + 1))

            let newSession = ChatSessionRecord(
                title: newTitle,
                modelConfigId: source.modelConfigId,
                systemPrompt: source.systemPrompt,
                createdAt: clock.now,
                updatedAt: clock.now
            )
            sessionStorage[newSession.id] = newSession
            // Duplicate the messages with fresh UUIDs so they don't collide with the source.
            messageStorage[newSession.id] = preserved.map { source -> ChatMessageDTO in
                ChatMessageDTO(
                    id: UUID(),
                    role: source.role,
                    content: source.content,
                    timestamp: source.timestamp
                )
            }
            return newSession
        }
    }

    public func recordTokenUsage(_ usage: TokenUsage, for sessionId: UUID) {
        lock.withLock {
            let existing = usageStorage[sessionId] ?? TokenUsage(promptTokens: 0, completionTokens: 0)
            usageStorage[sessionId] = TokenUsage(
                promptTokens: existing.promptTokens + usage.promptTokens,
                completionTokens: existing.completionTokens + usage.completionTokens
            )
        }
    }

    public func tokenUsage(for sessionId: UUID) -> TokenUsage {
        lock.withLock {
            usageStorage[sessionId] ?? TokenUsage(promptTokens: 0, completionTokens: 0)
        }
    }

    public func search(query: String, limit: Int) -> [ChatMessageSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.lowercased()

        return lock.withLock {
            var hits: [ChatMessageSearchHit] = []
            for (sessionId, messages) in messageStorage {
                guard let session = sessionStorage[sessionId], !session.isDeleted else { continue }
                for message in messages where message.content.lowercased().contains(needle) {
                    hits.append(
                        ChatMessageSearchHit(
                            sessionId: sessionId,
                            sessionTitle: session.title,
                            message: message
                        )
                    )
                }
            }
            hits.sort { $0.message.timestamp > $1.message.timestamp }
            return Array(hits.prefix(max(1, limit)))
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
