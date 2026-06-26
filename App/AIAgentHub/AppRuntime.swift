import Foundation
import Observation
import SwiftData
import AIAgentHubCore

@Observable
@MainActor
final class AppRuntime: AppAuthorizationPresenter {
    let chatRepository: any ChatRepository
    let modelRepository: any ModelConfigRepository
    let secretStore: any SecretStore
    let modelManager: ModelConfigurationManager
    let auditStore: SwiftDataAuditLogStore?
    let memoryAuditStore: InMemoryAuditLogStore?
    let toolRegistry: ToolRegistry
    let deviceRepository: InMemoryBoundDeviceRepository
    let remoteCommandLogStore: InMemoryRemoteCommandLogStore
    let deviceCoordinator: DeviceCoordinator
    let deviceConnectionService: any DeviceConnectionService
    let privacyPreferencesRepository: any PrivacyPreferencesRepository
    let lastSessionStore: any LastSessionStore
    let generationTracker: ActiveGenerationTracker
    private let retentionDaysBox: RetentionDaysBox
    private let authorizationBroker: AppAuthorizationBroker
    var modelConfigs: [ModelConfigRecord]
    var sessions: [ChatSessionRecord]
    var privacyPreferences: PrivacyPreferences
    var pendingAuthorization: AuthorizationRequest?
    /// Bumps whenever a message is appended/deleted/edited. The chat transcript view
    /// reads this in its body so SwiftUI re-fetches messages from the SwiftData
    /// repository — which is not observable on its own. Bump via `messagesChanged()`.
    var messageRevision: Int = 0
    var boundDevices: [BoundDevice] {
        deviceCoordinator.boundDevices()
    }
    var remoteCommandEntries: [RemoteCommandLogEntry] {
        remoteCommandLogStore.entries
    }
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
        authorizationBroker = AppAuthorizationBroker()
        let retentionBox = RetentionDaysBox(days: 30)
        retentionDaysBox = retentionBox
        toolRegistry = ToolRegistry(
            tools: Self.makeDefaultTools(),
            auditStore: auditStore,
            authorization: authorizationBroker,
            retentionDaysProvider: { retentionBox.days }
        )
        deviceRepository = InMemoryBoundDeviceRepository()
        remoteCommandLogStore = InMemoryRemoteCommandLogStore()
        deviceConnectionService = BonjourDeviceDiscoveryService(
            fallbackSender: MockDeviceConnectionService()
        )
        deviceCoordinator = DeviceCoordinator(
            connectionService: deviceConnectionService,
            repository: deviceRepository,
            authorization: authorizationBroker,
            logStore: remoteCommandLogStore
        )
        privacyPreferencesRepository = UserDefaultsPrivacyPreferencesRepository()
        lastSessionStore = UserDefaultsLastSessionStore()
        generationTracker = ActiveGenerationTracker()
        modelManager = ModelConfigurationManager(
            repository: modelRepository,
            secretStore: secretStore
        )
        modelConfigs = []
        sessions = []
        privacyPreferences = privacyPreferencesRepository.load()
        authorizationBroker.presenter = self
        retentionBox.days = privacyPreferences.retainAuditLogsDays
        seedDefaultsIfNeeded()
        refreshSessions()
    }

    init(secretStore: any SecretStore = KeyValueSecretStore()) {
        chatRepository = InMemoryChatRepository()
        modelRepository = InMemoryModelConfigRepository()
        self.secretStore = secretStore
        auditStore = nil
        let memoryAuditStore = InMemoryAuditLogStore()
        self.memoryAuditStore = memoryAuditStore
        authorizationBroker = AppAuthorizationBroker()
        let retentionBox = RetentionDaysBox(days: 30)
        retentionDaysBox = retentionBox
        toolRegistry = ToolRegistry(
            tools: Self.makeDefaultTools(),
            auditStore: memoryAuditStore,
            authorization: authorizationBroker,
            retentionDaysProvider: { retentionBox.days }
        )
        deviceRepository = InMemoryBoundDeviceRepository()
        remoteCommandLogStore = InMemoryRemoteCommandLogStore()
        deviceConnectionService = MockDeviceConnectionService(
            devices: [
                DiscoveredDevice(name: "Demo Mac", host: "192.168.1.20", port: 41_731, kind: .mac)
            ]
        )
        deviceCoordinator = DeviceCoordinator(
            connectionService: deviceConnectionService,
            repository: deviceRepository,
            authorization: authorizationBroker,
            logStore: remoteCommandLogStore
        )
        privacyPreferencesRepository = InMemoryPrivacyPreferencesRepository()
        lastSessionStore = InMemoryLastSessionStore()
        generationTracker = ActiveGenerationTracker()
        modelManager = ModelConfigurationManager(
            repository: modelRepository,
            secretStore: secretStore
        )
        modelConfigs = []
        sessions = []
        privacyPreferences = privacyPreferencesRepository.load()
        authorizationBroker.presenter = self
        retentionBox.days = privacyPreferences.retainAuditLogsDays
        seedDefaultsIfNeeded()
        refreshSessions()
    }

    func refreshModels() {
        modelConfigs = modelRepository.all(includeDisabled: true)
    }

    func refreshSessions() {
        sessions = chatRepository.sessions(includeDeleted: false)
    }

    /// Bump the message revision counter to force any chat view that subscribed via
    /// `_ = runtime.messageRevision` to re-fetch from the SwiftData repository. Necessary
    /// because the repository's `messages(for:)` is a direct fetch, not @Observable —
    /// without this nudge the user's own message wouldn't appear in the transcript until
    /// model streaming side-effects fire.
    func messagesChanged() {
        messageRevision &+= 1
    }

    /// Returns the last-opened session if it still exists, isn't archived, and isn't deleted.
    /// Use this on app launch to restore the user's place.
    func restorableSessionId() -> UUID? {
        guard let lastId = lastSessionStore.load() else { return nil }
        guard let session = chatRepository.session(id: lastId) else { return nil }
        guard !session.isArchived, !session.isDeleted else { return nil }
        return lastId
    }

    func rememberOpenSession(_ sessionId: UUID?) {
        lastSessionStore.save(sessionId)
    }

    func updatePrivacyPreferences(_ preferences: PrivacyPreferences) {
        privacyPreferences = preferences
        privacyPreferencesRepository.save(preferences)
        retentionDaysBox.days = preferences.retainAuditLogsDays
    }

    @discardableResult
    func createSession(title: String = "New Chat") -> ChatSessionRecord {
        let session = chatRepository.createSession(
            title: title,
            modelConfigId: modelManager.defaultModel()?.id
        )
        refreshSessions()
        return session
    }

    func renameSession(_ id: UUID, title: String) {
        chatRepository.renameSession(id, title: title)
        refreshSessions()
    }

    func togglePin(_ id: UUID) {
        guard let session = chatRepository.session(id: id) else { return }
        chatRepository.setSessionPinned(id, isPinned: !session.isPinned)
        refreshSessions()
    }

    func deleteSession(_ id: UUID) {
        chatRepository.softDeleteSession(id)
        refreshSessions()
    }

    func archiveSession(_ id: UUID) {
        chatRepository.archiveSession(id)
        refreshSessions()
    }

    func bindModelToSession(_ sessionId: UUID, modelId: UUID?) {
        chatRepository.setSessionModel(sessionId, modelConfigId: modelId)
        refreshSessions()
    }

    func setSystemPrompt(_ sessionId: UUID, prompt: String?) {
        chatRepository.setSessionSystemPrompt(sessionId, systemPrompt: prompt)
        refreshSessions()
    }

    /// Whether the model bound to this session (or the default model if none is bound) has an
    /// API key configured. Apple foundation models always count as configured.
    func sessionHasAPIKey(_ sessionId: UUID) -> Bool {
        guard let session = chatRepository.session(id: sessionId) else { return false }
        let modelRecord: ModelConfigRecord?
        if let bound = session.modelConfigId {
            modelRecord = modelConfigs.first { $0.id == bound && $0.isEnabled }
        } else {
            modelRecord = modelConfigs.first { $0.isDefault && $0.isEnabled }
                ?? modelConfigs.first { $0.isEnabled }
        }
        guard let model = modelRecord else { return false }
        return modelHasAPIKey(model: model)
    }

    /// Quick check used by the Models card to show "已配置 / 缺密钥" badges.
    func modelHasAPIKey(_ modelId: UUID) -> Bool {
        guard let model = modelConfigs.first(where: { $0.id == modelId }) else { return false }
        return modelHasAPIKey(model: model)
    }

    private func modelHasAPIKey(model: ModelConfigRecord) -> Bool {
        if model.provider == .apple { return true }
        let resolver = APIKeyResolver(secretStore: secretStore)
        let key = resolver.secretKey(for: model)
        return (try? secretStore.read(key))?.isEmpty == false
    }

    func resolvedModelName(for sessionId: UUID) -> String? {
        guard let session = chatRepository.session(id: sessionId) else { return nil }
        if let bound = session.modelConfigId,
           let record = modelConfigs.first(where: { $0.id == bound }) {
            return record.name
        }
        return modelConfigs.first { $0.isDefault && $0.isEnabled }?.name
    }

    func cancelActiveGeneration() {
        Task { await generationTracker.cancel() }
    }

    func deleteMessage(_ id: UUID, in sessionId: UUID) {
        chatRepository.deleteMessage(id, in: sessionId)
        messagesChanged()
    }

    func updateMessageContent(_ id: UUID, in sessionId: UUID, newContent: String) {
        chatRepository.updateMessageContent(id, in: sessionId, newContent: newContent)
        messagesChanged()
    }

    func deleteMessagesAfter(_ id: UUID, in sessionId: UUID) {
        chatRepository.deleteMessagesAfter(id, in: sessionId)
        messagesChanged()
    }

    func toggleBookmark(_ id: UUID, in sessionId: UUID) {
        chatRepository.toggleBookmark(id, in: sessionId)
        messagesChanged()
    }

    @discardableResult
    func branchSession(from sessionId: UUID, atMessage messageId: UUID) -> ChatSessionRecord? {
        guard let original = chatRepository.session(id: sessionId) else { return nil }
        let newTitle: String
        if original.title.hasSuffix(" (branch)") {
            newTitle = original.title
        } else {
            newTitle = "\(original.title) (branch)"
        }
        let result = chatRepository.branchSession(
            sessionId,
            upToMessageId: messageId,
            newTitle: newTitle
        )
        refreshSessions()
        return result
    }

    func tokenUsage(for sessionId: UUID) -> TokenUsage {
        chatRepository.tokenUsage(for: sessionId)
    }

    func searchMessages(_ query: String, limit: Int = 25) -> [ChatMessageSearchHit] {
        chatRepository.search(query: query, limit: limit)
    }

    func exportMarkdown(for sessionId: UUID) -> String? {
        exportConversation(for: sessionId, format: .markdown)
    }

    func exportConversation(for sessionId: UUID, format: ConversationExportFormat) -> String? {
        guard let session = chatRepository.session(id: sessionId) else { return nil }
        let messages = chatRepository.messages(for: sessionId)
        let usage = chatRepository.tokenUsage(for: sessionId)
        return ConversationExporter().export(
            sessionTitle: session.title,
            messages: messages,
            tokenUsage: usage.promptTokens + usage.completionTokens > 0 ? usage : nil,
            format: format
        )
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

    func clearChatHistory() {
        chatRepository.clearAllSessions()
    }

    func clearToolLogs() async {
        if let auditStore {
            await auditStore.clearAll()
        }
        if let memoryAuditStore {
            await memoryAuditStore.clearAll()
        }
    }

    func clearRemoteCommandLogs() async {
        await remoteCommandLogStore.clearAll()
    }

    func purgeExpiredData() async {
        chatRepository.purgeExpiredDeletedSessions()
        if let auditStore {
            await auditStore.clearExpired(now: Date())
        }
        if let memoryAuditStore {
            await memoryAuditStore.clearExpired(now: Date())
        }
    }

    private static func makeDefaultTools() -> [any Tool] {
        // Base provider-neutral tools — summarisation + web fetch — plus the iOS-only
        // device capability tools (alarms, calendar events, sandbox file writes). The
        // capability tools are gated by ToolAuthorization at execute time, so the user
        // still confirms each side-effect.
        var tools: [any Tool] = [TextSummaryTool(), WebFetchTool()]
        tools.append(contentsOf: DeviceCapabilityTools.makeAll())
        return tools
    }

    private func seedDefaultsIfNeeded() {
        // We used to pre-seed cards for OpenAI / DeepSeek / Claude / Volcengine here so the
        // user saw something on first launch. In practice that produced four empty "needs key"
        // cards which was visually noisy and made the Models tab look unconfigured. We now
        // start with an empty list — the page shows DSEmptyState pointing at the "+" button,
        // and each card the user creates is a deliberate choice tied to one provider.
        refreshModels()
    }
}

extension AppRuntime {
    func resolvePendingAuthorization(approved: Bool) {
        pendingAuthorization?.continuation.resume(returning: approved)
        pendingAuthorization = nil
    }
}

/// Tiny reference-typed box holding the current audit-log retention day count. Allows the
/// closure handed to `ToolRegistry` to read the up-to-date value without rebuilding the
/// registry every time the user moves the retention slider.
final class RetentionDaysBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int

    var days: Int {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = max(1, newValue) } }
    }

    init(days: Int) {
        self.storage = max(1, days)
    }
}
