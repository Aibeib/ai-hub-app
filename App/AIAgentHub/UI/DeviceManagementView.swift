import SwiftUI
import AIAgentHubCore

struct DeviceManagementView: View {
    @State private var discoveredDevices: [DiscoveredDevice] = [
        DiscoveredDevice(name: "Demo Mac", host: "192.168.1.20", port: 41731, kind: .mac)
    ]
    @State private var boundDevices: [BoundDevice] = []
    @State private var manualHost = ""
    @State private var statusMessage = "Cross-device execution is scaffolded for the MVP. Real Bonjour pairing belongs to the next phase."

    private let service = MockDeviceConnectionService(
        devices: [
            DiscoveredDevice(name: "Demo Mac", host: "192.168.1.20", port: 41731, kind: .mac)
        ]
    )

    var body: some View {
        List {
            Section("Discovered") {
                ForEach(discoveredDevices) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("\(device.host):\(device.port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Pair") {
                            Task {
                                if let bound = try? await service.pair(device) {
                                    boundDevices.append(bound)
                                    statusMessage = "Paired \(bound.name)"
                                }
                            }
                        }
                    }
                }
            }

            Section("Manual IP fallback") {
                TextField("Mac IP address", text: $manualHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add manual device") {
                    let device = BoundDevice(
                        name: "Manual Mac",
                        host: manualHost,
                        port: 41731,
                        kind: .mac
                    )
                    boundDevices.append(device)
                    statusMessage = "Added manual endpoint \(manualHost)"
                }
                .disabled(manualHost.isEmpty)
            }

            Section("Bound devices") {
                if boundDevices.isEmpty {
                    Text("No bound devices yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(boundDevices) { device in
                        Label("\(device.name) · \(device.host)", systemImage: "desktopcomputer")
                    }
                }
            }

            Section("Status") {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Devices")
    }
}

