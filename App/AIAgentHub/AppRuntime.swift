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
    private let authorizationBroker: AppAuthorizationBroker
    var modelConfigs: [ModelConfigRecord]
    var sessions: [ChatSessionRecord]
    var privacyPreferences: PrivacyPreferences
    var pendingAuthorization: AuthorizationRequest?
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
        toolRegistry = ToolRegistry(
            tools: [TextSummaryTool()],
            auditStore: auditStore,
            authorization: authorizationBroker
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
        authorizationBroker.presenter = self
        modelManager = ModelConfigurationManager(
            repository: modelRepository,
            secretStore: secretStore
        )
        modelConfigs = []
        sessions = []
        privacyPreferences = privacyPreferencesRepository.load()
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
        toolRegistry = ToolRegistry(
            tools: [TextSummaryTool()],
            auditStore: memoryAuditStore,
            authorization: authorizationBroker
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
        authorizationBroker.presenter = self
        modelManager = ModelConfigurationManager(
            repository: modelRepository,
            secretStore: secretStore
        )
        modelConfigs = []
        sessions = []
        privacyPreferences = privacyPreferencesRepository.load()
        seedDefaultsIfNeeded()
        refreshSessions()
    }

    func refreshModels() {
        modelConfigs = modelRepository.all(includeDisabled: true)
    }

    func refreshSessions() {
        sessions = chatRepository.sessions(includeDeleted: false)
    }

    func updatePrivacyPreferences(_ preferences: PrivacyPreferences) {
        privacyPreferences = preferences
        privacyPreferencesRepository.save(preferences)
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

    private func seedDefaultsIfNeeded() {
        guard modelRepository.all(includeDisabled: true).isEmpty else {
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

extension AppRuntime {
    func resolvePendingAuthorization(approved: Bool) {
        pendingAuthorization?.continuation.resume(returning: approved)
        pendingAuthorization = nil
    }
}
