import Foundation

/// Format the user can choose when exporting a conversation.
public enum ConversationExportFormat: String, CaseIterable, Sendable {
    case markdown
    case json

    public var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .json: "json"
        }
    }

    public var displayName: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        }
    }
}

/// Exports a session's messages to either Markdown or JSON.
///
/// Markdown output is single human-readable string with role headers, timestamps, and content
/// separated by thematic breaks. JSON output is a structured document with full metadata
/// (ids, roles, timestamps, token usage) so it can be re-imported by tooling.
public struct ConversationExporter: Sendable {
    public let dateFormatter: DateFormatter

    public init() {
        let fm = DateFormatter()
        fm.dateStyle = .medium
        fm.timeStyle = .short
        fm.locale = Locale.current
        self.dateFormatter = fm
    }

    /// Backwards-compatible Markdown export — preserved so existing callers don't break.
    public func export(sessionTitle: String, messages: [ChatMessageDTO], tokenUsage: TokenUsage?) -> String {
        export(sessionTitle: sessionTitle, messages: messages, tokenUsage: tokenUsage, format: .markdown)
    }

    /// Format-aware export. Returns the rendered document string.
    public func export(
        sessionTitle: String,
        messages: [ChatMessageDTO],
        tokenUsage: TokenUsage?,
        format: ConversationExportFormat
    ) -> String {
        switch format {
        case .markdown:
            renderMarkdown(sessionTitle: sessionTitle, messages: messages, tokenUsage: tokenUsage)
        case .json:
            renderJSON(sessionTitle: sessionTitle, messages: messages, tokenUsage: tokenUsage)
        }
    }

    private func renderMarkdown(sessionTitle: String, messages: [ChatMessageDTO], tokenUsage: TokenUsage?) -> String {
        var lines: [String] = []
        lines.append("# \(sessionTitle)\n")

        for message in messages {
            let ts = dateFormatter.string(from: message.timestamp)
            switch message.role {
            case .user:
                lines.append("## You (\(ts))\n")
                lines.append(message.content)
                lines.append("")

            case .assistant:
                lines.append("## Assistant (\(ts))\n")
                lines.append(message.content)
                lines.append("")

            case .tool:
                lines.append("## Tool call (\(ts))\n")
                lines.append("```text")
                lines.append(message.content)
                lines.append("```\n")

            case .system:
                lines.append("## System (\(ts))\n")
                lines.append(message.content)
                lines.append("")
            }
        }

        if let usage = tokenUsage {
            lines.append("---")
            lines.append("_Token usage: \(usage.promptTokens) prompt → \(usage.completionTokens) completion_")
        }

        return lines.joined(separator: "\n")
    }

    private func renderJSON(sessionTitle: String, messages: [ChatMessageDTO], tokenUsage: TokenUsage?) -> String {
        let document = JSONDocument(
            title: sessionTitle,
            exportedAt: Date(),
            messages: messages.map { JSONDocument.Message(from: $0) },
            tokenUsage: tokenUsage.map(JSONDocument.Usage.init(from:))
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(document),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private struct JSONDocument: Encodable {
        let title: String
        let exportedAt: Date
        let messages: [Message]
        let tokenUsage: Usage?

        struct Message: Encodable {
            let id: UUID
            let role: String
            let content: String
            let timestamp: Date

            init(from dto: ChatMessageDTO) {
                self.id = dto.id
                self.role = dto.role.rawValue
                self.content = dto.content
                self.timestamp = dto.timestamp
            }
        }

        struct Usage: Encodable {
            let promptTokens: Int
            let completionTokens: Int

            init(from usage: TokenUsage) {
                self.promptTokens = usage.promptTokens
                self.completionTokens = usage.completionTokens
            }
        }
    }
}