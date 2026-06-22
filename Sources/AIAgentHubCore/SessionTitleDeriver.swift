import Foundation

/// Derives a short, human-readable session title from the first user message.
///
/// Rules:
/// - Trim whitespace and newlines
/// - Collapse internal whitespace runs to a single space
/// - Strip trailing punctuation that's noisy in a title
/// - Truncate to `maxCharacters` on a word boundary when possible, append "…"
/// - Fall back to `fallback` when the input is empty or only whitespace
public struct SessionTitleDeriver: Sendable {
    public let maxCharacters: Int
    public let fallback: String

    public init(maxCharacters: Int = 40, fallback: String = "New Chat") {
        self.maxCharacters = max(8, maxCharacters)
        self.fallback = fallback
    }

    public func derive(from message: String) -> String {
        let normalized = normalize(message)
        guard !normalized.isEmpty else {
            return fallback
        }

        guard normalized.count > maxCharacters else {
            return normalized
        }

        // Try to cut on a word boundary inside the budget. We allow up to maxCharacters
        // characters before the ellipsis, so we look for the last space within that prefix.
        let cutoff = normalized.index(normalized.startIndex, offsetBy: maxCharacters)
        let prefix = String(normalized[..<cutoff])
        if let lastSpace = prefix.lastIndex(of: " "), prefix.distance(from: prefix.startIndex, to: lastSpace) > maxCharacters / 2 {
            return String(prefix[..<lastSpace]) + "…"
        }
        return prefix + "…"
    }

    private func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        // Strip trailing line-noise punctuation that makes titles look odd.
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?。、，；：！？\""))
    }
}
