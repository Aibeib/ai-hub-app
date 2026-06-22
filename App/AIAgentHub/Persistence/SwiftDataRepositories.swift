import Foundation
import SwiftData
import AIAgentHubCore

@MainActor
final class SwiftDataModelConfigRepository: ModelConfigRepository, @unchecked Sendable {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func upsert(_ config: ModelConfigRecord) {
        if config.isDefault {
            for model in fetchAllStored() {
                model.isDefault = false
            }
        }

        if let existing = fetchStored(id: config.id) {
            existing.apply(config)
        } else {
            context.insert(StoredModelConfig(record: config))
        }
        save()
    }

    func all(includeDisabled: Bool = true) -> [ModelConfigRecord] {
        fetchAllStored()
            .map(\.record)
            .filter { includeDisabled || $0.isEnabled }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func defaultModel() -> ModelConfigRecord? {
        let records = all(includeDisabled: false)
        return records.first { $0.isDefault } ?? records.first
    }

    func delete(id: UUID) {
        if let existing = fetchStored(id: id) {
            context.delete(existing)
            save()
        }
    }

    private func fetchAllStored() -> [StoredModelConfig] {
        let descriptor = FetchDescriptor<StoredModelConfig>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchStored(id: UUID) -> StoredModelConfig? {
        fetchAllStored().first { $0.id == id }
    }

    private func save() {
        try? context.save()
    }
}

@MainActor
final class SwiftDataChatRepository: ChatRepository, @unchecked Sendable {
    private let context: ModelContext
    private let clock: any Clock

    init(context: ModelContext, clock: any Clock = SystemClock()) {
        self.context = context
        self.clock = clock
    }

    @discardableResult
    func createSession(title: String, modelConfigId: UUID?) -> ChatSessionRecord {
        let record = ChatSessionRecord(
            title: title,
            modelConfigId: modelConfigId,
            createdAt: clock.now,
            updatedAt: clock.now
        )
        context.insert(StoredChatSession(record: record))
        save()
        return record
    }

    func sessions(includeDeleted: Bool = false) -> [ChatSessionRecord] {
        fetchAllSessions()
            .map(\.record)
            .filter { includeDeleted || !$0.isDeleted }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func session(id: UUID) -> ChatSessionRecord? {
        fetchSession(id: id)?.record
    }

    @discardableResult
    func appendMessage(_ message: ChatMessageDTO, to sessionId: UUID) -> ChatMessageDTO {
        guard let session = fetchSession(id: sessionId) else {
            return message
        }

        let stored = StoredChatMessage(message: message)
        stored.session = session
        session.messages.append(stored)
        session.updatedAt = clock.now
        context.insert(stored)
        save()
        return message
    }

    func messages(for sessionId: UUID) -> [ChatMessageDTO] {
        fetchSession(id: sessionId)?
            .messages
            .map(\.dto)
            .sorted { $0.timestamp < $1.timestamp } ?? []
    }

    func renameSession(_ sessionId: UUID, title: String) {
        guard let session = fetchSession(id: sessionId) else {
            return
        }
        session.title = title
        session.updatedAt = clock.now
        save()
    }

    func archiveSession(_ sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else {
            return
        }
        session.isArchived = true
        session.updatedAt = clock.now
        save()
    }

    func softDeleteSession(_ sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else {
            return
        }
        session.isDeleted = true
        session.deleteExpireAt = clock.now.addingTimeInterval(7 * 24 * 60 * 60)
        session.updatedAt = clock.now
        save()
    }

    func purgeExpiredDeletedSessions() {
        for session in fetchAllSessions() {
            if session.isDeleted, let deleteExpireAt = session.deleteExpireAt, deleteExpireAt <= clock.now {
                context.delete(session)
            }
        }
        save()
    }

    private func fetchAllSessions() -> [StoredChatSession] {
        let descriptor = FetchDescriptor<StoredChatSession>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchSession(id: UUID) -> StoredChatSession? {
        fetchAllSessions().first { $0.id == id }
    }

    private func save() {
        try? context.save()
    }
}

@MainActor
final class SwiftDataAuditLogStore: AuditLogStore, @unchecked Sendable {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    var entries: [ToolExecutionLogEntry] {
        let descriptor = FetchDescriptor<StoredToolExecutionLog>()
        return ((try? context.fetch(descriptor)) ?? [])
            .map(\.entry)
            .sorted { $0.createdAt > $1.createdAt }
    }

    func append(_ entry: ToolExecutionLogEntry) async {
        context.insert(StoredToolExecutionLog(entry: entry))
        try? context.save()
    }
}

