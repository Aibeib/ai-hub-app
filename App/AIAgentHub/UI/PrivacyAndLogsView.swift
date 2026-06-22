import SwiftUI
import AIAgentHubCore

struct PrivacyAndLogsView: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var showingClearChatConfirm = false
    @State private var showingClearLogsConfirm = false
    @State private var showingClearRemoteConfirm = false

    private var prefs: PrivacyPreferences { runtime.privacyPreferences }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                // Header
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Privacy")
                        .font(DS.Typography.display)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text("Your conversations stay on this device. Tool calls require explicit approval, and sensitive text is redacted before being sent.")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineSpacing(3)
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.lg)

                // Toggles
                DSSectionHeader("Data Controls")

                VStack(spacing: 0) {
                    PrivacyToggleRow(
                        icon: "network",
                        title: "Allow third-party API calls",
                        subtitle: "Send messages to providers like OpenAI, DeepSeek, and Anthropic.",
                        isOn: Binding(
                            get: { prefs.allowThirdPartyAPIs },
                            set: { runtime.updatePrivacyPreferences(prefs.with(allowThirdPartyAPIs: $0)) }
                        )
                    )
                    Divider().overlay(DS.Palette.separator).padding(.leading, 56)
                    PrivacyToggleRow(
                        icon: "wifi",
                        title: "Local network discovery",
                        subtitle: "Use Bonjour to find Macs on your local network for cross-device execution.",
                        isOn: Binding(
                            get: { prefs.enableLocalNetworkDiscovery },
                            set: { runtime.updatePrivacyPreferences(prefs.with(enableLocalNetworkDiscovery: $0)) }
                        )
                    )
                    Divider().overlay(DS.Palette.separator).padding(.leading, 56)
                    PrivacyToggleRow(
                        icon: "eye.slash",
                        title: "Redact before sending",
                        subtitle: "Replace file paths, emails, phone numbers, and device names with placeholders.",
                        isOn: Binding(
                            get: { prefs.redactBeforeSending },
                            set: { runtime.updatePrivacyPreferences(prefs.with(redactBeforeSending: $0)) }
                        )
                    )
                }
                .dsCard()
                .padding(.horizontal, DS.Space.xl)

                // Retention
                DSSectionHeader("Retention")

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack {
                        Text("Audit log retention")
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Palette.textPrimary)
                        Spacer()
                        Text("\(prefs.retainAuditLogsDays) days")
                            .font(DS.Typography.caption.monospacedDigit())
                            .foregroundStyle(DS.Palette.textSecondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(prefs.retainAuditLogsDays) },
                            set: { runtime.updatePrivacyPreferences(prefs.with(retainAuditLogsDays: Int($0))) }
                        ),
                        in: 1...90,
                        step: 1
                    )
                    .tint(DS.Palette.accent)

                    HStack {
                        Text("1 day")
                            .font(DS.Typography.captionSmall)
                            .foregroundStyle(DS.Palette.textTertiary)
                        Spacer()
                        Text("90 days")
                            .font(DS.Typography.captionSmall)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }

                    Text("Deleted conversations are kept in a recoverable state for 7 days before being permanently removed.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .padding(.top, DS.Space.xs)
                }
                .padding(DS.Space.md)
                .dsCard()
                .padding(.horizontal, DS.Space.xl)

                // Destructive actions
                DSSectionHeader("Clear Data")

                VStack(spacing: DS.Space.sm) {
                    DestructiveActionRow(
                        title: "Clear chat history",
                        subtitle: "All conversations on this device.",
                        action: { showingClearChatConfirm = true }
                    )
                    DestructiveActionRow(
                        title: "Clear tool execution logs",
                        subtitle: "Audit trail of approved and denied tool calls.",
                        action: { showingClearLogsConfirm = true }
                    )
                    DestructiveActionRow(
                        title: "Clear remote command logs",
                        subtitle: "Cross-device command history.",
                        action: { showingClearRemoteConfirm = true }
                    )
                    Button {
                        Task { await runtime.purgeExpiredData() }
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(DS.Palette.textSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Purge expired data now")
                                    .font(DS.Typography.callout.weight(.medium))
                                    .foregroundStyle(DS.Palette.textPrimary)
                                Text("Run retention cleanup ahead of schedule.")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.Palette.textTertiary)
                        }
                        .padding(DS.Space.md)
                        .dsCard()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DS.Space.xl)

                // Audit log
                let entries = runtime.auditEntries
                DSSectionHeader("Tool Execution Audit")

                if entries.isEmpty {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text("No tool calls recorded yet.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    .padding(.horizontal, DS.Space.xl)
                } else {
                    VStack(spacing: DS.Space.xs) {
                        ForEach(entries) { entry in
                            AuditEntryCard(entry: entry)
                        }
                    }
                    .padding(.horizontal, DS.Space.xl)
                }

                // Footer
                Text("Tool execution logs are retained for \(prefs.retainAuditLogsDays) days. Code execution, file mutation, deletion, and remote device commands always prompt for confirmation.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.bottom, DS.Space.xxl)
            }
        }
        .background(DS.Palette.surface)
        .confirmationDialog("Clear chat history?", isPresented: $showingClearChatConfirm) {
            Button("Delete all conversations", role: .destructive) {
                runtime.clearChatHistory()
                runtime.refreshSessions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every conversation on this device.")
        }
        .confirmationDialog("Clear tool execution logs?", isPresented: $showingClearLogsConfirm) {
            Button("Delete logs", role: .destructive) {
                Task { await runtime.clearToolLogs() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear remote command logs?", isPresented: $showingClearRemoteConfirm) {
            Button("Delete logs", role: .destructive) {
                Task { await runtime.clearRemoteCommandLogs() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Row components

private struct PrivacyToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(DS.Palette.accentSoft)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Palette.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typography.callout.weight(.medium))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(subtitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(DS.Palette.accent)
        }
        .padding(DS.Space.md)
    }
}

private struct DestructiveActionRow: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Palette.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Typography.callout.weight(.medium))
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(DS.Space.md)
            .dsCard()
        }
        .buttonStyle(.plain)
    }
}

private struct AuditEntryCard: View {
    let entry: ToolExecutionLogEntry

    private var decisionColor: Color {
        switch entry.decision {
        case .approved: DS.Palette.positive
        case .cancelled, .denied: DS.Palette.textTertiary
        }
    }

    private var riskColor: Color {
        switch entry.riskLevel {
        case .high: DS.Palette.danger
        case .medium: DS.Palette.warning
        case .low: DS.Palette.textSecondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            ZStack {
                Circle()
                    .fill(decisionColor.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: entry.decision == .approved ? "checkmark" : "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(decisionColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.toolName)
                    .font(DS.Typography.subheadline)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(entry.summary)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                HStack(spacing: DS.Space.xs) {
                    DSBadge(text: entry.riskLevel.rawValue, tint: riskColor)
                    DSBadge(text: entry.decision.rawValue, tint: decisionColor, filled: false)
                    Spacer()
                    Text(entry.createdAt, style: .relative)
                        .font(DS.Typography.captionSmall)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
        }
        .padding(DS.Space.sm + 2)
        .dsCard(DS.Radius.md)
    }
}

// MARK: - PrivacyPreferences convenience

private extension PrivacyPreferences {
    func with(
        allowThirdPartyAPIs: Bool? = nil,
        enableLocalNetworkDiscovery: Bool? = nil,
        redactBeforeSending: Bool? = nil,
        retainAuditLogsDays: Int? = nil
    ) -> PrivacyPreferences {
        PrivacyPreferences(
            allowThirdPartyAPIs: allowThirdPartyAPIs ?? self.allowThirdPartyAPIs,
            enableLocalNetworkDiscovery: enableLocalNetworkDiscovery ?? self.enableLocalNetworkDiscovery,
            redactBeforeSending: redactBeforeSending ?? self.redactBeforeSending,
            retainAuditLogsDays: retainAuditLogsDays ?? self.retainAuditLogsDays
        )
    }
}