import Foundation

/// A user-typeable slash command in the chat input. Resolved client-side; never sent verbatim
/// to a provider.
public enum SlashCommand: String, CaseIterable, Identifiable, Sendable {
    case system     // /system <prompt> → set the session system prompt
    case preset     // /preset → open the preset picker
    case clear      // /clear → delete all messages in the session
    case code       // /code <lang> <body> → wrap in a fenced code block before sending
    case branch     // /branch → fork session at the last assistant message
    case help       // /help → list commands

    public var id: String { rawValue }

    public var prefix: String {
        "/\(rawValue)"
    }

    public var summary: String {
        switch self {
        case .system: "Set or clear the system prompt"
        case .preset: "Pick a preset prompt"
        case .clear: "Delete all messages in this conversation"
        case .code: "Wrap your message in a fenced code block"
        case .branch: "Fork the conversation at the last assistant reply"
        case .help: "Show available commands"
        }
    }

    public var usage: String {
        switch self {
        case .system: "/system <new prompt>"
        case .preset: "/preset"
        case .clear: "/clear"
        case .code: "/code <language> <body>"
        case .branch: "/branch"
        case .help: "/help"
        }
    }
}

public enum ParsedSlashCommand: Equatable, Sendable {
    /// `/<known command> <args>` — args may be empty
    case command(SlashCommand, args: String)
    /// Input did not parse as a known command (either no leading slash, or unknown name).
    case notACommand
}

public enum SlashCommandParser {
    /// Recognize a leading slash command in user input. Returns `.notACommand` for input that
    /// doesn't start with `/` or whose name isn't a known command. Leading whitespace is
    /// tolerated.
    public static func parse(_ raw: String) -> ParsedSlashCommand {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return .notACommand }

        // Strip the leading slash, then split on the first whitespace into name + remainder.
        let withoutSlash = String(trimmed.dropFirst())
        let parts = withoutSlash.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let nameRaw = parts.first else { return .notACommand }
        let name = String(nameRaw).lowercased()
        guard let command = SlashCommand(rawValue: name) else { return .notACommand }

        let args: String
        if parts.count > 1 {
            args = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            args = ""
        }
        return .command(command, args: args)
    }

    /// Filter commands whose name matches a partial prefix typed after `/`.
    /// For example "/sy" → [.system]; "/" → all commands.
    public static func suggestions(forPrefix raw: String) -> [SlashCommand] {
        guard raw.hasPrefix("/") else { return [] }
        let stripped = raw.dropFirst().lowercased()
        guard !stripped.contains(" ") else { return [] }
        let filter = stripped
        return SlashCommand.allCases.filter { command in
            filter.isEmpty || command.rawValue.hasPrefix(filter)
        }
    }
}
