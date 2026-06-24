import Foundation
import AIAgentHubCore

/// Built-in catalog of common model variants per provider. Used by the model editor to offer
/// a friendly picker instead of asking users to remember exact model strings. Users can still
/// fall back to a free-form custom model name.
enum ModelVariantCatalog {
    struct Variant: Identifiable, Hashable, Sendable {
        let id: String         // canonical model name sent to the provider
        let displayName: String
        let summary: String

        init(_ id: String, displayName: String, summary: String) {
            self.id = id
            self.displayName = displayName
            self.summary = summary
        }
    }

    static func variants(for provider: ModelProvider) -> [Variant] {
        switch provider {
        case .openai:
            return [
                Variant("gpt-4o", displayName: "GPT-4o", summary: "旗舰多模态"),
                Variant("gpt-4o-mini", displayName: "GPT-4o mini", summary: "便宜的多模态"),
                Variant("gpt-4.1", displayName: "GPT-4.1", summary: "更强推理 / 编码"),
                Variant("gpt-4.1-mini", displayName: "GPT-4.1 mini", summary: "便宜，日常对话"),
                Variant("o4-mini", displayName: "o4-mini", summary: "推理模型 / 数学")
            ]
        case .deepseek:
            // 官方将于 2026/07/24 弃用 deepseek-chat / deepseek-reasoner，
            // 全量切换到 deepseek-v4-flash / deepseek-v4-pro。当前两组都保留以便兼容。
            return [
                Variant("deepseek-v4-pro", displayName: "DeepSeek V4 Pro", summary: "更强能力，推荐"),
                Variant("deepseek-v4-flash", displayName: "DeepSeek V4 Flash", summary: "极速 · 便宜"),
                Variant("deepseek-chat", displayName: "DeepSeek Chat (legacy)", summary: "旧版聊天，2026-07-24 停用"),
                Variant("deepseek-reasoner", displayName: "DeepSeek Reasoner (legacy)", summary: "旧版推理，2026-07-24 停用")
            ]
        case .anthropic:
            return [
                Variant("claude-sonnet-4-6", displayName: "Claude Sonnet 4.6", summary: "当前最强代码模型"),
                Variant("claude-opus-4-8", displayName: "Claude Opus 4.8", summary: "最深推理"),
                Variant("claude-haiku-4-5-20251001", displayName: "Claude Haiku 4.5", summary: "便宜 · 快"),
                Variant("claude-sonnet-4-5", displayName: "Claude Sonnet 4.5", summary: "上一代主力")
            ]
        case .volcengine:
            // 火山方舟需要在控制台创建「在线推理接入点」拿到 endpoint id（形如 ep-xxxxxxxx-xxxxx）
            // 用户通常自己粘贴自己的 endpoint id，所以列表只给一个示例占位 + 引导走自定义。
            return [
                Variant("doubao-pro-4k", displayName: "豆包 Pro 4k", summary: "通用旗舰"),
                Variant("doubao-pro-32k", displayName: "豆包 Pro 32k", summary: "长上下文"),
                Variant("doubao-lite-4k", displayName: "豆包 Lite 4k", summary: "极速 · 便宜"),
                Variant("doubao-1-5-pro-32k-250115", displayName: "豆包 1.5 Pro", summary: "更强推理")
            ]
        case .apple:
            return [
                Variant("apple-foundation", displayName: "Apple Foundation", summary: "完全本地 · iOS 26+")
            ]
        }
    }

    /// Whether a given (provider, modelName) pair matches one of the built-in variants.
    static func matchesBuiltIn(provider: ModelProvider, modelName: String) -> Bool {
        variants(for: provider).contains { $0.id == modelName }
    }

    /// Default variant id for a freshly-added provider entry.
    static func defaultVariantId(for provider: ModelProvider) -> String {
        variants(for: provider).first?.id ?? ""
    }
}
