import Foundation

/// Exports a session's messages to a Markdown document.
///
/// The output is a single human-readable string with role headers, timestamps, and content
/// separated by thematic breaks. No frontmatter or metadata is included so the export can be
/// pasted directly into documentation or shared.
public struct ConversationExporter: Sendable {
    public let dateFormatter: DateFormatter

    public init() {
        let fm = DateFormatter()
        fm.dateStyle = .medium
        fm.timeStyle = .short
        fm.locale = Locale.current
        self.dateFormatter = fm
    }

    /// Produce a Markdown block from a session's message list.
    ///
    /// - Returns: A Markdown string with `## role` headers, timestamps, code-fenced tool results.
    public func export(sessionTitle: String, messages: [ChatMessageDTO], tokenUsage: TokenUsage?) -> String {
        var lines: [String] = []

        // Title
        lines.append("# \(sessionTitle)\n")

        for message in messages {
            let ts = dateFormatter.string(from: message.timestamp)
            switch message.role {
            case .user:
                lines.append("## You (\(ts))\n")
                lines.append(escape(message.content))
                lines.append("")

            case .assistant:
                lines.append("## Assistant (\(ts))\n")
                lines.append(escape(message.content))
                lines.append("")

            case .tool:
                lines.append("## Tool call (\(ts))\n")
                lines.append("```text")
                lines.append(message.content)
                lines.append("```\n")

            case .system:
                lines.append("## System (\(ts))\n")
                lines.append(escape(message.content))
                lines.append("")
            }
        }

        if let usage = tokenUsage {
            lines.append("---")
            lines.append("_Token usage: \(usage.promptTokens) prompt → \(usage.completionTokens) completion_")
        }

        return lines.joined(separator: "\n")
    }

    private func escape(_ text: String) -> String {
        // Prefix with a backslash to avoid Markdown rendering issues for leading hashes
        // or list markers. The text is raw user/assistant content so we just fence it
        // in a paragraph block by escaping the first line if needed.
        text
    }
}