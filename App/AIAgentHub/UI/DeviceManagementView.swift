import SwiftUI
import AIAgentHubCore

struct DeviceManagementView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.appLanguage) private var language
    @State private var discoveredDevices: [DiscoveredDevice] = []
    @State private var manualHost = ""
    @State private var commandText = "Create a draft report"
    @State private var highRiskCommand = false
    @State private var statusMessage: String?
    @State private var isScanning = false
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case manualHost
        case command
    }

    private var boundDevices: [BoundDevice] { runtime.boundDevices }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                // Header
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(language[.devicesTitle])
                        .font(DS.Typography.display)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(language[.devicesSubtitle])
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineSpacing(3)
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.lg)

                // Discovered
                DSSectionHeader(
                    language[.devicesSectionDiscovered],
                    trailing: AnyView(
                        HStack(spacing: DS.Space.sm) {
                            if isScanning {
                                ProgressView().scaleEffect(0.7)
                            }

                            Button {
                                isScanning = true
                                Task {
                                    for await event in runtime.deviceConnectionService.discover() {
                                        switch event {
                                        case let .found(device):
                                            if !discoveredDevices.contains(where: { $0.id == device.id }) {
                                                withAnimation(DS.Motion.springSnappy) {
                                                    discoveredDevices.append(device)
                                                }
                                            }
                                        case let .removed(id):
                                            withAnimation(DS.Motion.springSnappy) {
                                                discoveredDevices.removeAll { $0.id == id }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(DS.Palette.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    )
                )

                if discoveredDevices.isEmpty {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text(isScanning ? language[.devicesScanning] : language[.devicesEmptyDiscovered])
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    .padding(.horizontal, DS.Space.xl)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: DS.Space.lg)], spacing: DS.Space.lg) {
                        ForEach(discoveredDevices) { device in
                            DeviceCard(
                                kind: .discovered,
                                name: device.name,
                                detail: "\(device.host):\(device.port)",
                                status: .idle,
                                action: (label: language[.devicesActionPair], run: {
                                    Task {
                                        do {
                                            let bound = try await runtime.deviceCoordinator.pair(device)
                                            statusMessage = (language == .zh ? "已配对 " : "Paired ") + bound.name
                                        } catch {
                                            statusMessage = (language == .zh ? "配对失败: " : "Pairing failed: ") + error.localizedDescription
                                        }
                                    }
                                })
                            )
                        }
                    }
                    .padding(.horizontal, DS.Space.xl)
                }

                // Manual IP
                DSSectionHeader(language[.devicesSectionAddManually])

                HStack(spacing: DS.Space.sm) {
                    TextField(language[.devicesManualPlaceholder], text: $manualHost)
                        .textFieldStyle(.plain)
                        .font(DS.Typography.callout)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focusedField, equals: .manualHost)
                        .onSubmit {
                            focusedField = nil
                        }
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, DS.Space.xs + 2)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .fill(DS.Palette.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .stroke(DS.Palette.border, lineWidth: 0.5)
                        )

                    Button {
                        focusedField = nil
                        KeyboardDismissal.dismiss()
                        _ = runtime.deviceCoordinator.addManualMac(
                            name: "Manual Mac",
                            host: manualHost,
                            port: 41_731
                        )
                        statusMessage = (language == .zh ? "已添加 " : "Added ") + manualHost
                        manualHost = ""
                    } label: {
                        Text(language[.devicesManualAdd])
                            .font(DS.Typography.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.vertical, DS.Space.xs)
                            .background(
                                Capsule().fill(manualHost.isEmpty ? DS.Palette.textTertiary : DS.Palette.accent)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(manualHost.isEmpty)
                }
                .padding(.horizontal, DS.Space.xl)

                // Bound
                DSSectionHeader(language[.devicesSectionConnected])

                if boundDevices.isEmpty {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text(language[.devicesEmptyConnected])
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    .padding(.horizontal, DS.Space.xl)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: DS.Space.lg)], spacing: DS.Space.lg) {
                        ForEach(boundDevices) { device in
                            DeviceCard(
                                kind: .bound,
                                name: device.name,
                                detail: device.host,
                                status: .live,
                                action: nil
                            )
                        }
                    }
                    .padding(.horizontal, DS.Space.xl)
                }

                // Remote command
                if !boundDevices.isEmpty {
                    DSSectionHeader(language[.devicesSectionRemoteCommand])

                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        TextField(language[.devicesCommandInstructionPlaceholder], text: $commandText, axis: .vertical)
                            .lineLimit(1...3)
                            .textFieldStyle(.plain)
                            .font(DS.Typography.body)
                            .submitLabel(.send)
                            .focused($focusedField, equals: .command)
                            .onSubmit {
                                if let firstDevice = boundDevices.first {
                                    Task { await sendCommand(to: firstDevice) }
                                }
                            }
                            .padding(.horizontal, DS.Space.sm)
                            .padding(.vertical, DS.Space.xs + 2)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                    .fill(DS.Palette.surfaceElevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                    .stroke(DS.Palette.border, lineWidth: 0.5)
                            )

                        Toggle(isOn: $highRiskCommand) {
                            HStack(spacing: DS.Space.xs) {
                                Text(language[.devicesCommandHighRisk])
                                    .font(DS.Typography.callout)
                                if highRiskCommand {
                                    DSStatusDot(status: .warn, animated: true)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(DS.Palette.warning)

                        HStack {
                            ForEach(boundDevices) { device in
                                Button {
                                    focusedField = nil
                                    KeyboardDismissal.dismiss()
                                    Task { await sendCommand(to: device) }
                                } label: {
                                    Label(String(format: language[.devicesCommandSend], device.name), systemImage: "arrow.up.message")
                                        .font(DS.Typography.caption.weight(.semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(highRiskCommand ? DS.Palette.warning : DS.Palette.accent)
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.xl)
                }

                // Logs
                let logs = runtime.remoteCommandEntries
                if !logs.isEmpty {
                    DSSectionHeader(language[.devicesSectionCommandLog])

                    ForEach(logs) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.summary)
                                .font(DS.Typography.callout)
                                .foregroundStyle(DS.Palette.textPrimary)
                            HStack(spacing: DS.Space.xs) {
                                DSBadge(text: entry.risk.rawValue, tint: entry.risk == .high ? DS.Palette.danger : DS.Palette.textSecondary)
                                DSBadge(text: entry.decision.rawValue, tint: DS.Palette.textSecondary)
                            }
                        }
                        .padding(DS.Space.md)
                        .dsCard()
                        .padding(.horizontal, DS.Space.xl)
                    }
                }

                // Status message
                if let statusMessage {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Palette.accent)
                        Text(statusMessage)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    .padding(.horizontal, DS.Space.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.bottom, DS.Space.xxl)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedField = nil
                        KeyboardDismissal.dismiss()
                    }
            }
        }
        .background(DS.Palette.surface)
        .scrollDismissesKeyboard(.interactively)
        .animation(DS.Motion.easeOut, value: statusMessage)
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
        focusedField = nil
        KeyboardDismissal.dismiss()
        let command = RemoteCommand(
            instruction: commandText,
            risk: highRiskCommand ? .high : .low
        )
        do {
            let result = try await runtime.deviceCoordinator.send(command, to: device)
            statusMessage = result.output
        } catch {
            statusMessage = (language == .zh ? "指令失败: " : "Command failed: ") + error.localizedDescription
        }
    }
}

// MARK: - Device card

private enum DeviceCardKind {
    case discovered, bound
}

private struct DeviceCard: View {
    let kind: DeviceCardKind
    let name: String
    let detail: String
    let status: DSStatusDot.Status
    let action: (label: String, run: () -> Void)?

    var body: some View {
        HStack(spacing: DS.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(kind == .bound ? DS.Palette.positive.opacity(0.12) : DS.Palette.accentSoft)
                    .frame(width: 44, height: 44)
                Image(systemName: kind == .bound ? "desktopcomputer" : "laptopcomputer")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(kind == .bound ? DS.Palette.positive : DS.Palette.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(detail)
                    .font(DS.Typography.monoSmall)
                    .foregroundStyle(DS.Palette.textTertiary)
            }

            Spacer()

            DSStatusDot(status: status, animated: false)

            if let action {
                Button(action: action.run) {
                    Text(action.label)
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(DS.Palette.accentSoft)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Space.md)
        .dsCard()
    }
}
