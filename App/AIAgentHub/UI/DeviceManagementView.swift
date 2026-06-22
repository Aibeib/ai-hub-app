import SwiftUI
import AIAgentHubCore

struct DeviceManagementView: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var discoveredDevices: [DiscoveredDevice] = []
    @State private var manualHost = ""
    @State private var commandText = "Create a draft report"
    @State private var highRiskCommand = false
    @State private var statusMessage = "Cross-device execution is scaffolded for the MVP. Real Bonjour pairing belongs to the next phase."

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
                                do {
                                    let bound = try await runtime.deviceCoordinator.pair(device)
                                    statusMessage = "Paired \(bound.name)"
                                } catch {
                                    statusMessage = "Pairing failed: \(error.localizedDescription)"
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
                    let device = runtime.deviceCoordinator.addManualMac(
                        name: "Manual Mac",
                        host: manualHost,
                        port: 41_731
                    )
                    statusMessage = "Added manual endpoint \(manualHost)"
                    manualHost = ""
                }
                .disabled(manualHost.isEmpty)
            }

            Section("Bound devices") {
                if runtime.boundDevices.isEmpty {
                    Text("No bound devices yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(runtime.boundDevices) { device in
                        VStack(alignment: .leading, spacing: 8) {
                            Label("\(device.name) · \(device.host)", systemImage: "desktopcomputer")
                            Button("Send command") {
                                Task { await sendCommand(to: device) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section("Remote command") {
                TextField("Instruction", text: $commandText, axis: .vertical)
                    .lineLimit(1...3)
                Toggle("High risk command", isOn: $highRiskCommand)
                Text("High-risk remote commands go through the same authorization/audit path. The current MVP uses an approved mock authorizer until the confirmation UI is wired.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Remote command logs") {
                if runtime.remoteCommandEntries.isEmpty {
                    Text("No remote commands yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(runtime.remoteCommandEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.summary)
                            Text("\(entry.risk.rawValue) · \(entry.decision.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Status") {
                Text(statusMessage)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Devices")
        .task {
            discoveredDevices = []
            for await event in runtime.deviceConnectionService.discover() {
                switch event {
                case let .found(device):
                    discoveredDevices.append(device)
                case let .removed(id):
                    discoveredDevices.removeAll { $0.id == id }
                }
            }
        }
    }

    private func sendCommand(to device: BoundDevice) async {
        let command = RemoteCommand(
            instruction: commandText,
            risk: highRiskCommand ? .high : .low
        )
        do {
            let result = try await runtime.deviceCoordinator.send(command, to: device)
            statusMessage = result.output
        } catch {
            statusMessage = "Command failed: \(error.localizedDescription)"
        }
    }
}
