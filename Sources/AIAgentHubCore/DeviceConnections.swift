import Foundation

public enum DeviceKind: String, Codable, Equatable, Sendable {
    case iPhone
    case iPad
    case mac
    case unknown
}

public struct DiscoveredDevice: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var kind: DeviceKind

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int,
        kind: DeviceKind
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.kind = kind
    }
}

public struct BoundDevice: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var kind: DeviceKind
    public var pairedAt: Date
    public var lastSeenAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int,
        kind: DeviceKind,
        pairedAt: Date = Date(),
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.kind = kind
        self.pairedAt = pairedAt
        self.lastSeenAt = lastSeenAt
    }
}

public enum DeviceDiscoveryEvent: Equatable, Sendable {
    case found(DiscoveredDevice)
    case removed(UUID)
}

public enum RemoteCommandRisk: String, Codable, Equatable, Sendable {
    case low
    case high
}

public struct RemoteCommand: Codable, Equatable, Sendable {
    public var id: UUID
    public var instruction: String
    public var risk: RemoteCommandRisk

    public init(id: UUID = UUID(), instruction: String, risk: RemoteCommandRisk) {
        self.id = id
        self.instruction = instruction
        self.risk = risk
    }
}

public struct RemoteCommandResult: Codable, Equatable, Sendable {
    public var commandId: UUID
    public var output: String
    public var completedAt: Date

    public init(commandId: UUID, output: String, completedAt: Date = Date()) {
        self.commandId = commandId
        self.output = output
        self.completedAt = completedAt
    }
}

public enum RemoteCommandAuthorizationDecision: String, Codable, Equatable, Sendable {
    case approved
    case cancelled
}

public struct RemoteCommandLogEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var deviceId: UUID
    public var commandId: UUID
    public var risk: RemoteCommandRisk
    public var decision: RemoteCommandAuthorizationDecision
    public var summary: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        deviceId: UUID,
        commandId: UUID,
        risk: RemoteCommandRisk,
        decision: RemoteCommandAuthorizationDecision,
        summary: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.deviceId = deviceId
        self.commandId = commandId
        self.risk = risk
        self.decision = decision
        self.summary = summary
        self.createdAt = createdAt
    }
}

public protocol RemoteCommandAuthorization: Sendable {
    func authorize(command: RemoteCommand, device: BoundDevice) async -> RemoteCommandAuthorizationDecision
}

public struct StaticRemoteCommandAuthorization: RemoteCommandAuthorization {
    private let decision: RemoteCommandAuthorizationDecision

    public init(decision: RemoteCommandAuthorizationDecision) {
        self.decision = decision
    }

    public func authorize(command: RemoteCommand, device: BoundDevice) async -> RemoteCommandAuthorizationDecision {
        decision
    }
}

public protocol BoundDeviceRepository: Sendable {
    func upsert(_ device: BoundDevice)
    func all() -> [BoundDevice]
    func delete(id: UUID)
}

public final class InMemoryBoundDeviceRepository: BoundDeviceRepository, @unchecked Sendable {
    private var storage: [UUID: BoundDevice] = [:]
    private let lock = NSLock()

    public init(devices: [BoundDevice] = []) {
        storage = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
    }

    public func upsert(_ device: BoundDevice) {
        lock.withLock {
            storage[device.id] = device
        }
    }

    public func all() -> [BoundDevice] {
        lock.withLock {
            storage.values.sorted { $0.name < $1.name }
        }
    }

    public func delete(id: UUID) {
        _ = lock.withLock {
            storage.removeValue(forKey: id)
        }
    }
}

public protocol RemoteCommandLogStore: Sendable {
    func append(_ entry: RemoteCommandLogEntry) async
}

public final class InMemoryRemoteCommandLogStore: RemoteCommandLogStore, @unchecked Sendable {
    private var storage: [RemoteCommandLogEntry] = []
    private let lock = NSLock()

    public init(entries: [RemoteCommandLogEntry] = []) {
        storage = entries
    }

    public var entries: [RemoteCommandLogEntry] {
        lock.withLock { storage }
    }

    public func append(_ entry: RemoteCommandLogEntry) async {
        lock.withLock {
            storage.append(entry)
        }
    }
}

public protocol DeviceConnectionService: Sendable {
    func discover() -> AsyncStream<DeviceDiscoveryEvent>
    func pair(_ device: DiscoveredDevice) async throws -> BoundDevice
    func send(_ command: RemoteCommand, to device: BoundDevice) async throws -> RemoteCommandResult
}

public enum DeviceCoordinatorError: Error, Equatable {
    case authorizationCancelled
}

public final class DeviceCoordinator: @unchecked Sendable {
    private let connectionService: any DeviceConnectionService
    private let repository: any BoundDeviceRepository
    private let authorization: any RemoteCommandAuthorization
    private let logStore: any RemoteCommandLogStore

    public init(
        connectionService: any DeviceConnectionService,
        repository: any BoundDeviceRepository,
        authorization: any RemoteCommandAuthorization,
        logStore: any RemoteCommandLogStore
    ) {
        self.connectionService = connectionService
        self.repository = repository
        self.authorization = authorization
        self.logStore = logStore
    }

    public func boundDevices() -> [BoundDevice] {
        repository.all()
    }

    @discardableResult
    public func pair(_ discoveredDevice: DiscoveredDevice) async throws -> BoundDevice {
        let bound = try await connectionService.pair(discoveredDevice)
        repository.upsert(bound)
        return bound
    }

    @discardableResult
    public func addManualMac(name: String, host: String, port: Int = 41_731) -> BoundDevice {
        let device = BoundDevice(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Manual Mac" : name,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            kind: .mac,
            pairedAt: Date(),
            lastSeenAt: nil
        )
        repository.upsert(device)
        return device
    }

    public func send(_ command: RemoteCommand, to device: BoundDevice) async throws -> RemoteCommandResult {
        let decision: RemoteCommandAuthorizationDecision
        if command.risk == .high {
            decision = await authorization.authorize(command: command, device: device)
        } else {
            decision = .approved
        }

        await logStore.append(
            RemoteCommandLogEntry(
                deviceId: device.id,
                commandId: command.id,
                risk: command.risk,
                decision: decision,
                summary: "\(device.name): \(command.instruction)"
            )
        )

        guard decision == .approved else {
            throw DeviceCoordinatorError.authorizationCancelled
        }

        return try await connectionService.send(command, to: device)
    }
}

public final class MockDeviceConnectionService: DeviceConnectionService, @unchecked Sendable {
    private let devices: [DiscoveredDevice]

    public init(devices: [DiscoveredDevice] = []) {
        self.devices = devices
    }

    public func discover() -> AsyncStream<DeviceDiscoveryEvent> {
        AsyncStream { continuation in
            for device in devices {
                continuation.yield(.found(device))
            }
            continuation.finish()
        }
    }

    public func pair(_ device: DiscoveredDevice) async throws -> BoundDevice {
        BoundDevice(
            id: device.id,
            name: device.name,
            host: device.host,
            port: device.port,
            kind: device.kind,
            pairedAt: Date(),
            lastSeenAt: Date()
        )
    }

    public func send(_ command: RemoteCommand, to device: BoundDevice) async throws -> RemoteCommandResult {
        RemoteCommandResult(
            commandId: command.id,
            output: "Mock result from \(device.name): \(command.instruction)"
        )
    }
}

public enum AppleFoundationAvailability {
    public static var isAvailable: Bool {
        if #available(iOS 26.0, macOS 26.0, *) {
            return true
        }
        return false
    }
}
