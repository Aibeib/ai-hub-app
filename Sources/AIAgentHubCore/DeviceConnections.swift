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

public protocol DeviceConnectionService: Sendable {
    func discover() -> AsyncStream<DeviceDiscoveryEvent>
    func pair(_ device: DiscoveredDevice) async throws -> BoundDevice
    func send(_ command: RemoteCommand, to device: BoundDevice) async throws -> RemoteCommandResult
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

