import Foundation
import Network
import AIAgentHubCore

final class BonjourDeviceDiscoveryService: DeviceConnectionService, @unchecked Sendable {
    private let serviceType: String
    private let queue: DispatchQueue
    private let fallbackSender: any DeviceConnectionService

    init(
        serviceType: String = "_aiagenthub._tcp",
        queue: DispatchQueue = DispatchQueue(label: "com.local.AIAgentHub.bonjour"),
        fallbackSender: any DeviceConnectionService = MockDeviceConnectionService()
    ) {
        self.serviceType = serviceType
        self.queue = queue
        self.fallbackSender = fallbackSender
    }

    func discover() -> AsyncStream<DeviceDiscoveryEvent> {
        AsyncStream { continuation in
            let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
            let browser = NWBrowser(for: descriptor, using: .tcp)

            browser.browseResultsChangedHandler = { results, changes in
                for change in changes {
                    switch change {
                    case let .added(result):
                        if let device = Self.device(from: result) {
                            continuation.yield(.found(device))
                        }
                    case let .removed(result):
                        if let device = Self.device(from: result) {
                            continuation.yield(.removed(device.id))
                        }
                    default:
                        continue
                    }
                }

                if changes.isEmpty {
                    for result in results {
                        if let device = Self.device(from: result) {
                            continuation.yield(.found(device))
                        }
                    }
                }
            }

            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                browser.cancel()
            }

            browser.start(queue: queue)
        }
    }

    func pair(_ device: DiscoveredDevice) async throws -> BoundDevice {
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

    func send(_ command: RemoteCommand, to device: BoundDevice) async throws -> RemoteCommandResult {
        try await fallbackSender.send(command, to: device)
    }

    private static func device(from result: NWBrowser.Result) -> DiscoveredDevice? {
        guard case let .service(name, type, domain, interface) = result.endpoint else {
            return nil
        }

        let stableId = UUID(uuidString: deterministicUUIDSeed("\(name).\(type).\(domain)")) ?? UUID()
        return DiscoveredDevice(
            id: stableId,
            name: name,
            host: interface?.debugDescription ?? domain,
            port: 41_731,
            kind: .mac
        )
    }

    private static func deterministicUUIDSeed(_ value: String) -> String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let suffix = String(format: "%012llx", hash & 0x0000_FFFF_FFFF_FFFF)
        return "00000000-0000-4000-8000-\(suffix)"
    }
}

