import Foundation
import SwiftUI

/// Lightweight localization layer. Every UI string in the app should route through
/// `L10n.t(.<key>, in: language)` so toggling the in-app language picker takes effect
/// immediately without re-launching. We deliberately avoid Apple's bundle-based
/// `String(localized:)` here so language can change mid-session.
///
/// Keys are organized by surface (`AppKey` cases). Add new cases — never inline raw
/// Chinese/English strings in views.
enum L10n {
    enum AppKey: String, CaseIterable {
        // Tabs
        case tabChat
        case tabModels
        case tabDevices
        case tabPrivacy

        // Chat home
        case chatTitle
        case chatHistory
        case chatNewConversation
        case chatEmptyTitle
        case chatEmptySubtitle
        case chatEmptyCTA
        case chatSearchPlaceholder
        case chatNoConversationsYet
        case chatNoSearchMatches
        case chatStartHint
        case chatInputPlaceholder
        case chatStartConversation
        case chatTotalCount

        // Transcript
        case transcriptAssistantRole
        case transcriptTypingLabel
        case transcriptFirstHintTitle
        case transcriptFirstHintSubtitle
        case transcriptTokensSuffix
        case transcriptToolResult

        // Menu actions
        case actionSwitchModel
        case actionSetSystemPrompt
        case actionEditSystemPrompt
        case actionRegenerate
        case actionExportMarkdown
        case actionExportJSON
        case actionPin
        case actionUnpin
        case actionArchive
        case actionDelete
        case actionCopy
        case actionBookmark
        case actionRemoveBookmark
        case actionEditMessage
        case actionBranchHere
        case actionDeleteMessage
        case actionRetry
        case actionDismiss
        case actionCancel
        case actionSave
        case actionDone
        case actionShare
        case actionClear

        // Banners / alerts
        case bannerAPIKeyMissingTitle
        case bannerAPIKeyMissingBodyForModel
        case bannerAPIKeyMissingBodyGeneric
        case bannerAPIKeyMissingCTA
        case alertMessageFailedTitle

        // Models tab
        case modelsTitle
        case modelsSubtitle
        case modelsSectionActive
        case modelsSectionInactive
        case modelsSectionOnDevice
        case modelsEmptyTitle
        case modelsEmptySubtitle
        case modelsEmptyCTA
        case modelsAddTitle
        case modelsEditTitle
        case modelsLabelDefault
        case modelsLabelDisabled
        case modelsLabelTemp
        case modelsLabelTokens
        case modelsFieldDisplayName
        case modelsFieldProvider
        case modelsFieldModelName
        case modelsFieldModelNamePicker
        case modelsFieldCustomModel
        case modelsFieldCustomModelHint
        case modelsFieldCustomEndpoint
        case modelsFieldAPIKey
        case modelsFieldAPIKeyReplace
        case modelsFieldKeychainNotice
        case modelsFieldTemperature
        case modelsFieldMaxTokens
        case modelsFieldIsDefault
        case modelsFieldIsEnabled
        case modelsSectionProvider
        case modelsSectionSecret
        case modelsSectionParameters
        case modelsAppleAvailable
        case modelsAppleRequires
        case modelsKeychainNotice

        // Devices
        case devicesTitle
        case devicesSubtitle
        case devicesSectionDiscovered
        case devicesSectionAddManually
        case devicesSectionConnected
        case devicesSectionRemoteCommand
        case devicesSectionCommandLog
        case devicesEmptyDiscovered
        case devicesScanning
        case devicesEmptyConnected
        case devicesActionPair
        case devicesManualPlaceholder
        case devicesManualAdd
        case devicesCommandInstructionPlaceholder
        case devicesCommandHighRisk
        case devicesCommandSend

        // Privacy
        case privacyTitle
        case privacySubtitle
        case privacyRetentionLabel
        case privacyClearChats
        case privacyClearLogs
        case privacyClearRemote
        case privacyLanguageSection
        case privacyLanguageLabel

        // Empty / sparkles
        case sparklesQuietTitle
        case sparklesQuietSubtitle
        case sparklesCTA

        // Misc
        case kPresetsTitle
        case kSystemPromptHint
    }

    static func t(_ key: AppKey, in language: AppLanguage) -> String {
        switch language {
        case .zh: return zh[key] ?? en[key] ?? key.rawValue
        case .en: return en[key] ?? key.rawValue
        }
    }

    // MARK: - Chinese

    private static let zh: [AppKey: String] = [
        .tabChat: "对话",
        .tabModels: "模型",
        .tabDevices: "设备",
        .tabPrivacy: "隐私",

        .chatTitle: "对话",
        .chatHistory: "历史会话",
        .chatNewConversation: "新建对话",
        .chatEmptyTitle: "开始第一次对话",
        .chatEmptySubtitle: "对话内容仅存储在本机。发送给第三方模型前会做隐私脱敏。",
        .chatEmptyCTA: "新建对话",
        .chatSearchPlaceholder: "搜索",
        .chatNoConversationsYet: "还没有会话",
        .chatNoSearchMatches: "没有匹配的会话",
        .chatStartHint: "输入消息开始对话",
        .chatInputPlaceholder: "给 AI Hub 发消息…（输入 / 查看命令）",
        .chatStartConversation: "开始对话",
        .chatTotalCount: "共 %d 个",

        .transcriptAssistantRole: "助手",
        .transcriptTypingLabel: "正在输入",
        .transcriptFirstHintTitle: "想问点什么？",
        .transcriptFirstHintSubtitle: "消息会先脱敏再发送。工具调用都需要你确认才会执行。",
        .transcriptTokensSuffix: "tokens",
        .transcriptToolResult: "工具结果",

        .actionSwitchModel: "切换模型",
        .actionSetSystemPrompt: "设置 System Prompt",
        .actionEditSystemPrompt: "编辑 System Prompt",
        .actionRegenerate: "重新生成",
        .actionExportMarkdown: "导出 Markdown",
        .actionExportJSON: "导出 JSON",
        .actionPin: "置顶",
        .actionUnpin: "取消置顶",
        .actionArchive: "归档",
        .actionDelete: "删除",
        .actionCopy: "复制",
        .actionBookmark: "收藏",
        .actionRemoveBookmark: "取消收藏",
        .actionEditMessage: "编辑消息",
        .actionBranchHere: "从此处分支",
        .actionDeleteMessage: "删除消息",
        .actionRetry: "重试",
        .actionDismiss: "知道了",
        .actionCancel: "取消",
        .actionSave: "保存",
        .actionDone: "完成",
        .actionShare: "分享",
        .actionClear: "清除",

        .bannerAPIKeyMissingTitle: "未配置 API Key",
        .bannerAPIKeyMissingBodyForModel: "%@ 还没有可用的 API Key，无法发送消息。",
        .bannerAPIKeyMissingBodyGeneric: "请先到「模型」中添加并启用一个模型。",
        .bannerAPIKeyMissingCTA: "去配置",
        .alertMessageFailedTitle: "消息发送失败",

        .modelsTitle: "模型",
        .modelsSubtitle: "选择要使用的 AI 服务，并为每个服务配置 API Key。",
        .modelsSectionActive: "已启用的服务",
        .modelsSectionInactive: "已停用",
        .modelsSectionOnDevice: "本机模型",
        .modelsEmptyTitle: "还没有可用的模型",
        .modelsEmptySubtitle: "添加 OpenAI、DeepSeek 或 Claude，给它一个 API Key 即可开始使用。",
        .modelsEmptyCTA: "添加模型",
        .modelsAddTitle: "添加模型",
        .modelsEditTitle: "编辑模型",
        .modelsLabelDefault: "默认",
        .modelsLabelDisabled: "已停用",
        .modelsLabelTemp: "温度",
        .modelsLabelTokens: "Tokens",
        .modelsFieldDisplayName: "显示名称",
        .modelsFieldProvider: "服务商",
        .modelsFieldModelName: "模型名",
        .modelsFieldModelNamePicker: "可用模型",
        .modelsFieldCustomModel: "自定义模型名",
        .modelsFieldCustomModelHint: "如果列表中没有你要的模型，可手动输入。",
        .modelsFieldCustomEndpoint: "自定义 Endpoint（可选）",
        .modelsFieldAPIKey: "API Key",
        .modelsFieldAPIKeyReplace: "新 API Key（留空则保留原值）",
        .modelsFieldKeychainNotice: "API Key 通过系统钥匙串加密存储，不会以明文形式保存。",
        .modelsFieldTemperature: "温度",
        .modelsFieldMaxTokens: "最大 tokens",
        .modelsFieldIsDefault: "设为默认",
        .modelsFieldIsEnabled: "启用",
        .modelsSectionProvider: "服务商",
        .modelsSectionSecret: "密钥",
        .modelsSectionParameters: "参数",
        .modelsAppleAvailable: "本机可用",
        .modelsAppleRequires: "需要 iOS 26 或更新版本",
        .modelsKeychainNotice: "API Key 通过系统钥匙串加密保存。",

        .devicesTitle: "设备",
        .devicesSubtitle: "在同一 Wi-Fi 下发现并配对 Mac，用于跨端任务执行。",
        .devicesSectionDiscovered: "已发现",
        .devicesSectionAddManually: "手动添加",
        .devicesSectionConnected: "已连接",
        .devicesSectionRemoteCommand: "发送远程指令",
        .devicesSectionCommandLog: "指令日志",
        .devicesEmptyDiscovered: "没有发现设备。请确认 Mac 与手机在同一 Wi-Fi 下。",
        .devicesScanning: "正在扫描本地网络…",
        .devicesEmptyConnected: "还没有已配对的设备。",
        .devicesActionPair: "配对",
        .devicesManualPlaceholder: "Mac 的 IP 地址",
        .devicesManualAdd: "添加",
        .devicesCommandInstructionPlaceholder: "指令",
        .devicesCommandHighRisk: "高风险",
        .devicesCommandSend: "发送至 %@",

        .privacyTitle: "隐私",
        .privacySubtitle: "本地优先。第三方 API 只看到脱敏后的内容。",
        .privacyRetentionLabel: "审计日志保留天数",
        .privacyClearChats: "清空所有会话",
        .privacyClearLogs: "清空审计日志",
        .privacyClearRemote: "清空远程指令日志",
        .privacyLanguageSection: "语言",
        .privacyLanguageLabel: "界面语言",

        .sparklesQuietTitle: "一个安静的思考空间",
        .sparklesQuietSubtitle: "对话存在本机。第三方 API 只看到脱敏文本——原始笔记永远不离开你的设备。",
        .sparklesCTA: "新建对话",

        .kPresetsTitle: "预设",
        .kSystemPromptHint: "System Prompt 影响这一次会话中助手的行为。留空使用模型默认设置。",
    ]

    // MARK: - English

    private static let en: [AppKey: String] = [
        .tabChat: "Chat",
        .tabModels: "Models",
        .tabDevices: "Devices",
        .tabPrivacy: "Privacy",

        .chatTitle: "Chat",
        .chatHistory: "Conversations",
        .chatNewConversation: "New conversation",
        .chatEmptyTitle: "Start your first conversation",
        .chatEmptySubtitle: "Conversations live on this device. Outbound traffic is redacted before it leaves.",
        .chatEmptyCTA: "New conversation",
        .chatSearchPlaceholder: "Search",
        .chatNoConversationsYet: "No conversations yet.",
        .chatNoSearchMatches: "No matches.",
        .chatStartHint: "Type a message to begin.",
        .chatInputPlaceholder: "Message AI Hub… (type / for commands)",
        .chatStartConversation: "Start a new conversation",
        .chatTotalCount: "%d total",

        .transcriptAssistantRole: "Assistant",
        .transcriptTypingLabel: "typing",
        .transcriptFirstHintTitle: "Ask me anything",
        .transcriptFirstHintSubtitle: "Your message is redacted before being sent. Tools always ask for approval.",
        .transcriptTokensSuffix: "tokens",
        .transcriptToolResult: "Tool result",

        .actionSwitchModel: "Switch model",
        .actionSetSystemPrompt: "Set system prompt",
        .actionEditSystemPrompt: "Edit system prompt",
        .actionRegenerate: "Regenerate last reply",
        .actionExportMarkdown: "Export as Markdown",
        .actionExportJSON: "Export as JSON",
        .actionPin: "Pin",
        .actionUnpin: "Unpin",
        .actionArchive: "Archive",
        .actionDelete: "Delete",
        .actionCopy: "Copy",
        .actionBookmark: "Bookmark",
        .actionRemoveBookmark: "Remove bookmark",
        .actionEditMessage: "Edit message",
        .actionBranchHere: "Branch from here",
        .actionDeleteMessage: "Delete message",
        .actionRetry: "Retry",
        .actionDismiss: "Dismiss",
        .actionCancel: "Cancel",
        .actionSave: "Save",
        .actionDone: "Done",
        .actionShare: "Share",
        .actionClear: "Clear",

        .bannerAPIKeyMissingTitle: "API key missing",
        .bannerAPIKeyMissingBodyForModel: "Add a provider key to use %@ — or pick a different model from the menu.",
        .bannerAPIKeyMissingBodyGeneric: "Set up a model from the Models tab before sending messages.",
        .bannerAPIKeyMissingCTA: "Open Models",
        .alertMessageFailedTitle: "Message failed",

        .modelsTitle: "Models",
        .modelsSubtitle: "Pick which AI providers to use and add an API key for each.",
        .modelsSectionActive: "Active providers",
        .modelsSectionInactive: "Inactive",
        .modelsSectionOnDevice: "On-device",
        .modelsEmptyTitle: "No models configured",
        .modelsEmptySubtitle: "Add a provider like OpenAI, DeepSeek, or Claude to get started.",
        .modelsEmptyCTA: "Add model",
        .modelsAddTitle: "Add model",
        .modelsEditTitle: "Edit model",
        .modelsLabelDefault: "Default",
        .modelsLabelDisabled: "Disabled",
        .modelsLabelTemp: "Temp",
        .modelsLabelTokens: "Tokens",
        .modelsFieldDisplayName: "Display name",
        .modelsFieldProvider: "Provider",
        .modelsFieldModelName: "Model name",
        .modelsFieldModelNamePicker: "Available models",
        .modelsFieldCustomModel: "Custom model name",
        .modelsFieldCustomModelHint: "Pick from the list, or enter a model name manually.",
        .modelsFieldCustomEndpoint: "Custom endpoint (optional)",
        .modelsFieldAPIKey: "API key",
        .modelsFieldAPIKeyReplace: "New API key (leave blank to keep)",
        .modelsFieldKeychainNotice: "Keys are saved through the Keychain-backed secret store.",
        .modelsFieldTemperature: "Temperature",
        .modelsFieldMaxTokens: "Max tokens",
        .modelsFieldIsDefault: "Default model",
        .modelsFieldIsEnabled: "Enabled",
        .modelsSectionProvider: "Provider",
        .modelsSectionSecret: "Secret",
        .modelsSectionParameters: "Parameters",
        .modelsAppleAvailable: "Available on this device",
        .modelsAppleRequires: "Requires iOS 26+",
        .modelsKeychainNotice: "API keys are stored in the system Keychain and are never persisted in plaintext.",

        .devicesTitle: "Devices",
        .devicesSubtitle: "Discover and pair with Macs on your local network for cross-device execution.",
        .devicesSectionDiscovered: "Discovered",
        .devicesSectionAddManually: "Add manually",
        .devicesSectionConnected: "Connected",
        .devicesSectionRemoteCommand: "Remote command",
        .devicesSectionCommandLog: "Command log",
        .devicesEmptyDiscovered: "No devices found. Make sure your Mac is on the same Wi-Fi network.",
        .devicesScanning: "Scanning your local network…",
        .devicesEmptyConnected: "No paired devices yet.",
        .devicesActionPair: "Pair",
        .devicesManualPlaceholder: "Mac IP address",
        .devicesManualAdd: "Add",
        .devicesCommandInstructionPlaceholder: "Instruction",
        .devicesCommandHighRisk: "High risk",
        .devicesCommandSend: "Send to %@",

        .privacyTitle: "Privacy",
        .privacySubtitle: "Local-first. Third-party APIs only see redacted text.",
        .privacyRetentionLabel: "Audit log retention (days)",
        .privacyClearChats: "Clear all conversations",
        .privacyClearLogs: "Clear audit logs",
        .privacyClearRemote: "Clear remote-command logs",
        .privacyLanguageSection: "Language",
        .privacyLanguageLabel: "Interface language",

        .sparklesQuietTitle: "A quiet place to think",
        .sparklesQuietSubtitle: "Conversations are stored locally on your device. Third-party APIs only see redacted text — your raw notes stay here.",
        .sparklesCTA: "Start a new conversation",

        .kPresetsTitle: "Presets",
        .kSystemPromptHint: "System prompt steers the assistant's behaviour for this conversation. Leave it blank to use the model's defaults.",
    ]
}

extension AppLanguage {
    /// Convenience so views can write `language[.tabChat]` instead of `L10n.t(.tabChat, in:)`.
    subscript(_ key: L10n.AppKey) -> String {
        L10n.t(key, in: self)
    }
}
