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

    func restoreSession(_ sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else {
            return
        }
        session.isDeleted = false
        session.deleteExpireAt = nil
        session.updatedAt = clock.now
        save()
    }

    func setSessionModel(_ sessionId: UUID, modelConfigId: UUID?) {
        guard let session = fetchSession(id: sessionId) else {
            return
        }
        session.modelConfigId = modelConfigId
        session.updatedAt = clock.now
        save()
    }

    func setSessionPinned(_ sessionId: UUID, isPinned: Bool) {
        guard let session = fetchSession(id: sessionId) else {
            return
        }
        session.isPinned = isPinned
        session.updatedAt = clock.now
        save()
    }

    func setSessionSystemPrompt(_ sessionId: UUID, systemPrompt: String?) {
        guard let session = fetchSession(id: sessionId) else {
            return
        }
        let trimmed = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        session.systemPrompt = (trimmed?.isEmpty ?? true) ? nil : trimmed
        session.updatedAt = clock.now
        save()
    }

    func deleteMessage(_ messageId: UUID, in sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else { return }
        if let stored = session.messages.first(where: { $0.id == messageId }) {
            context.delete(stored)
            session.updatedAt = clock.now
            save()
        }
    }

    func updateMessageContent(_ messageId: UUID, in sessionId: UUID, newContent: String) {
        guard let session = fetchSession(id: sessionId),
              let stored = session.messages.first(where: { $0.id == messageId }) else { return }
        stored.content = newContent
        session.updatedAt = clock.now
        save()
    }

    func deleteMessagesAfter(_ messageId: UUID, in sessionId: UUID) {
        guard let session = fetchSession(id: sessionId),
              let cutoffMessage = session.messages.first(where: { $0.id == messageId }) else { return }
        let cutoffTime = cutoffMessage.timestamp
        let toDelete = session.messages.filter { $0.timestamp > cutoffTime }
        for stored in toDelete {
            context.delete(stored)
        }
        session.updatedAt = clock.now
        save()
    }

    @discardableResult
    func branchSession(_ sourceSessionId: UUID, upToMessageId: UUID, newTitle: String) -> ChatSessionRecord? {
        guard let source = fetchSession(id: sourceSessionId) else { return nil }
        let ordered = source.messages.sorted { $0.timestamp < $1.timestamp }
        guard let cutoffMessage = ordered.first(where: { $0.id == upToMessageId }) else { return nil }
        let cutoffTime = cutoffMessage.timestamp
        let preserved = ordered.filter { $0.timestamp <= cutoffTime }

        let now = clock.now
        let newRecord = ChatSessionRecord(
            title: newTitle,
            modelConfigId: source.modelConfigId,
            systemPrompt: source.systemPrompt,
            createdAt: now,
            updatedAt: now
        )
        let newStored = StoredChatSession(record: newRecord)
        context.insert(newStored)

        for original in preserved {
            let copy = StoredChatMessage(
                message: ChatMessageDTO(
                    id: UUID(),
                    role: MessageRole(rawValue: original.roleRawValue) ?? .assistant,
                    content: original.content,
                    timestamp: original.timestamp
                )
            )
            copy.session = newStored
            newStored.messages.append(copy)
            context.insert(copy)
        }

        save()
        return newRecord
    }

    func recordTokenUsage(_ usage: TokenUsage, for sessionId: UUID) {
        guard let session = fetchSession(id: sessionId) else { return }
        session.totalPromptTokens += usage.promptTokens
        session.totalCompletionTokens += usage.completionTokens
        save()
    }

    func tokenUsage(for sessionId: UUID) -> TokenUsage {
        guard let session = fetchSession(id: sessionId) else {
            return TokenUsage(promptTokens: 0, completionTokens: 0)
        }
        return TokenUsage(
            promptTokens: session.totalPromptTokens,
            completionTokens: session.totalCompletionTokens
        )
    }

    func search(query: String, limit: Int) -> [ChatMessageSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        var hits: [ChatMessageSearchHit] = []
        for session in fetchAllSessions() where !session.isDeleted {
            for stored in session.messages where stored.content.lowercased().contains(trimmed) {
                hits.append(
                    ChatMessageSearchHit(
                        sessionId: session.id,
                        sessionTitle: session.title,
                        message: stored.dto
                    )
                )
            }
        }
        hits.sort { $0.message.timestamp > $1.message.timestamp }
        return Array(hits.prefix(max(1, limit)))
    }

    func purgeExpiredDeletedSessions() {
        for session in fetchAllSessions() {
            if session.isDeleted, let deleteExpireAt = session.deleteExpireAt, deleteExpireAt <= clock.now {
                context.delete(session)
            }
        }
        save()
    }

    func clearAllSessions() {
        for session in fetchAllSessions() {
            context.delete(session)
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

    func clearExpired(now: Date) async {
        let descriptor = FetchDescriptor<StoredToolExecutionLog>()
        let stored = (try? context.fetch(descriptor)) ?? []
        for entry in stored where entry.expiresAt <= now {
            context.delete(entry)
        }
        try? context.save()
    }

    func clearAll() async {
        let descriptor = FetchDescriptor<StoredToolExecutionLog>()
        let stored = (try? context.fetch(descriptor)) ?? []
        for entry in stored {
            context.delete(entry)
        }
        try? context.save()
    }
}
