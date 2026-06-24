import SwiftUI
import AIAgentHubCore

struct PrivacyAndLogsView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(AppLanguagePreference.self) private var languagePref
    @Environment(\.appLanguage) private var language
    @State private var showingClearChatConfirm = false
    @State private var showingClearLogsConfirm = false
    @State private var showingClearRemoteConfirm = false

    private var prefs: PrivacyPreferences { runtime.privacyPreferences }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                // Header
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(language[.privacyTitle])
                        .font(DS.Typography.display)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(language[.privacySubtitle])
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineSpacing(3)
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.lg)

                // Language picker
                DSSectionHeader(language[.privacyLanguageSection])

                HStack(spacing: DS.Space.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DS.Palette.accentSoft)
                            .frame(width: 32, height: 32)
                        Image(systemName: "globe")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.Palette.accent)
                    }
                    Text(language[.privacyLanguageLabel])
                        .font(DS.Typography.callout.weight(.medium))
                        .foregroundStyle(DS.Palette.textPrimary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { languagePref.current },
                        set: { languagePref.current = $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(DS.Palette.accent)
                }
                .padding(DS.Space.md)
                .dsCard()
                .padding(.horizontal, DS.Space.xl)

                // Toggles
                DSSectionHeader(language == .zh ? "数据控制" : "Data Controls")

                VStack(spacing: 0) {
                    PrivacyToggleRow(
                        icon: "network",
                        title: language == .zh ? "允许调用第三方 API" : "Allow third-party API calls",
                        subtitle: language == .zh
                            ? "向 OpenAI、DeepSeek、Claude 等服务商发送消息。"
                            : "Send messages to providers like OpenAI, DeepSeek, and Anthropic.",
                        isOn: Binding(
                            get: { prefs.allowThirdPartyAPIs },
                            set: { runtime.updatePrivacyPreferences(prefs.with(allowThirdPartyAPIs: $0)) }
                        )
                    )
                    Divider().overlay(DS.Palette.separator).padding(.leading, 56)
                    PrivacyToggleRow(
                        icon: "wifi",
                        title: language == .zh ? "本地网络发现" : "Local network discovery",
                        subtitle: language == .zh
                            ? "通过 Bonjour 在局域网内发现 Mac，用于跨端执行。"
                            : "Use Bonjour to find Macs on your local network for cross-device execution.",
                        isOn: Binding(
                            get: { prefs.enableLocalNetworkDiscovery },
                            set: { runtime.updatePrivacyPreferences(prefs.with(enableLocalNetworkDiscovery: $0)) }
                        )
                    )
                    Divider().overlay(DS.Palette.separator).padding(.leading, 56)
                    PrivacyToggleRow(
                        icon: "eye.slash",
                        title: language == .zh ? "发送前脱敏" : "Redact before sending",
                        subtitle: language == .zh
                            ? "把文件路径、邮箱、电话号码、设备名替换成占位符。"
                            : "Replace file paths, emails, phone numbers, and device names with placeholders.",
                        isOn: Binding(
                            get: { prefs.redactBeforeSending },
                            set: { runtime.updatePrivacyPreferences(prefs.with(redactBeforeSending: $0)) }
                        )
                    )
                }
                .dsCard()
                .padding(.horizontal, DS.Space.xl)

                // Retention
                DSSectionHeader(language == .zh ? "保留时间" : "Retention")

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    HStack {
                        Text(language[.privacyRetentionLabel])
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Palette.textPrimary)
                        Spacer()
                        Text(language == .zh ? "\(prefs.retainAuditLogsDays) 天" : "\(prefs.retainAuditLogsDays) days")
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
                        Text(language == .zh ? "1 天" : "1 day")
                            .font(DS.Typography.captionSmall)
                            .foregroundStyle(DS.Palette.textTertiary)
                        Spacer()
                        Text(language == .zh ? "90 天" : "90 days")
                            .font(DS.Typography.captionSmall)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }

                    Text(language == .zh
                         ? "已删除的会话会进入 7 天恢复期，过期后永久删除。"
                         : "Deleted conversations are kept in a recoverable state for 7 days before being permanently removed.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .padding(.top, DS.Space.xs)
                }
                .padding(DS.Space.md)
                .dsCard()
                .padding(.horizontal, DS.Space.xl)

                // Destructive actions
                DSSectionHeader(language == .zh ? "清空数据" : "Clear Data")

                VStack(spacing: DS.Space.sm) {
                    DestructiveActionRow(
                        title: language[.privacyClearChats],
                        subtitle: language == .zh ? "本机的所有对话。" : "All conversations on this device.",
                        action: { showingClearChatConfirm = true }
                    )
                    DestructiveActionRow(
                        title: language[.privacyClearLogs],
                        subtitle: language == .zh ? "审计记录中的所有工具调用。" : "Audit trail of approved and denied tool calls.",
                        action: { showingClearLogsConfirm = true }
                    )
                    DestructiveActionRow(
                        title: language[.privacyClearRemote],
                        subtitle: language == .zh ? "跨设备指令记录。" : "Cross-device command history.",
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
                                Text(language == .zh ? "立即清理过期数据" : "Purge expired data now")
                                    .font(DS.Typography.callout.weight(.medium))
                                    .foregroundStyle(DS.Palette.textPrimary)
                                Text(language == .zh ? "提前触发一次保留期清理。" : "Run retention cleanup ahead of schedule.")
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
                DSSectionHeader(language == .zh ? "工具调用审计" : "Tool Execution Audit")

                if entries.isEmpty {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text(language == .zh ? "还没有工具调用记录。" : "No tool calls recorded yet.")
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
                Text(language == .zh
                     ? "工具调用日志保留 \(prefs.retainAuditLogsDays) 天。代码执行、文件修改、删除、远程指令等敏感操作都需要你单独确认。"
                     : "Tool execution logs are retained for \(prefs.retainAuditLogsDays) days. Code execution, file mutation, deletion, and remote device commands always prompt for confirmation.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.bottom, DS.Space.xxl)
            }
        }
        .background(DS.Palette.surface)
        .confirmationDialog(language == .zh ? "确定清空所有对话？" : "Clear chat history?", isPresented: $showingClearChatConfirm) {
            Button(language == .zh ? "全部删除" : "Delete all conversations", role: .destructive) {
                runtime.clearChatHistory()
                runtime.refreshSessions()
            }
            Button(language[.actionCancel], role: .cancel) {}
        } message: {
            Text(language == .zh
                 ? "本机上所有的会话都会被永久删除。"
                 : "This permanently removes every conversation on this device.")
        }
        .confirmationDialog(language == .zh ? "清空审计日志？" : "Clear tool execution logs?", isPresented: $showingClearLogsConfirm) {
            Button(language == .zh ? "删除日志" : "Delete logs", role: .destructive) {
                Task { await runtime.clearToolLogs() }
            }
            Button(language[.actionCancel], role: .cancel) {}
        }
        .confirmationDialog(language == .zh ? "清空远程指令日志？" : "Clear remote command logs?", isPresented: $showingClearRemoteConfirm) {
            Button(language == .zh ? "删除日志" : "Delete logs", role: .destructive) {
                Task { await runtime.clearRemoteCommandLogs() }
            }
            Button(language[.actionCancel], role: .cancel) {}
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
        case .cancelled: DS.Palette.textTertiary
        }
    }

    private var riskColor: Color {
        switch entry.riskLevel {
        case .high: DS.Palette.danger
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