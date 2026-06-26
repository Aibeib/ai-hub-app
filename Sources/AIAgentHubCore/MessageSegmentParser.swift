import Foundation

/// Segmented representation of message content for rendering.
///
/// `Text(.init(markdown))` in SwiftUI handles inline markdown (bold, italic, links, inline
/// code) but does not handle fenced code blocks. The UI splits messages into segments at the
/// fence boundaries so each kind can be rendered with the right styling.
public enum MessageSegment: Equatable, Sendable {
    /// Inline text — may still contain markdown syntax handled by AttributedString.
    case inline(String)
    /// Fenced code block. `language` is the optional info string after the opening fence.
    case code(language: String?, body: String)
    /// Reasoning / chain-of-thought block. Rendered as a collapsible "Thinking" card —
    /// DeepSeek emits these as `reasoning_content` on its reasoner models, and several
    /// other providers wrap CoT in `<think>...</think>` tags inside the assistant text.
    case thinking(String)

    public var rawText: String {
        switch self {
        case let .inline(text):
            text
        case let .code(_, body):
            body
        case let .thinking(body):
            body
        }
    }
}

public enum MessageSegmentParser {
    /// Split a message into alternating inline / code / thinking segments.
    ///
    /// - `<think>...</think>` blocks become `.thinking` segments (also tolerates an
    ///   unclosed `<think>` during streaming — everything after the open tag is treated
    ///   as in-progress thinking until the close tag arrives or the message ends).
    /// - Triple-backtick fences inside the remaining content become `.code` blocks
    ///   (tolerates a missing closing fence).
    public static func parse(_ content: String) -> [MessageSegment] {
        // First pass: pull out `<think>...</think>` blocks. We do this before fence parsing
        // because the contents of a thinking block can legitimately contain backticks or
        // even fenced code, and we don't want those interpreted as the assistant's own
        // code blocks. Thinking takes precedence; whatever falls outside passes to fence
        // parsing.
        //
        // Streaming-safety: if the buffer ENDS with a partial open tag like `<th`,
        // `<thi`, `<thin`, or `<think` (no closing `>` yet), trim those bytes off before
        // parsing. Without this the parser flips between "inline" and "thinking" output
        // on every 1-character delta as the tag types itself out, and the visible bubble
        // structure rebuilds top-to-bottom each time — exactly the "bubble jumps" symptom
        // the user reported.
        let trimmed = stripTrailingPartialThinkTag(content)
        var output: [MessageSegment] = []
        var cursor = trimmed.startIndex
        let endIndex = trimmed.endIndex
        let openTag = "<think>"
        let closeTag = "</think>"

        while cursor < endIndex {
            guard let openRange = trimmed.range(of: openTag, range: cursor..<endIndex) else {
                // No more thinking blocks — parse remaining as code/inline.
                let tail = String(trimmed[cursor..<endIndex])
                output.append(contentsOf: parseFences(tail))
                break
            }
            // Emit everything before the open tag as regular content.
            if openRange.lowerBound > cursor {
                let before = String(trimmed[cursor..<openRange.lowerBound])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    output.append(contentsOf: parseFences(before))
                }
            }
            // Find the matching close tag. If it's missing (still streaming), treat the
            // rest of the buffer as thinking — the UI shows a "thinking..." indicator
            // and we'll re-parse cleanly once the close tag arrives.
            let afterOpen = openRange.upperBound
            if let closeRange = trimmed.range(of: closeTag, range: afterOpen..<endIndex) {
                let thought = String(trimmed[afterOpen..<closeRange.lowerBound])
                let body = thought.trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    output.append(.thinking(body))
                }
                cursor = closeRange.upperBound
            } else {
                let thought = String(trimmed[afterOpen..<endIndex])
                let body = thought.trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty {
                    output.append(.thinking(body))
                }
                break
            }
        }

        return output
    }

    /// If `content` ends with a still-incomplete `<think` (with up to 6 of the 7 chars,
    /// no closing `>`), return `content` with that fragment removed. We also handle a
    /// half-typed close tag (`</thin` etc.) by stopping at it: the open tag is already
    /// in the buffer, so the leftover after the unfinished close will still parse as
    /// thinking — just keep the unfinished suffix out of the visible body.
    ///
    /// This is intentionally conservative: we only strip the literal partial-tag suffix,
    /// not any other angle-bracket text in the message.
    private static func stripTrailingPartialThinkTag(_ content: String) -> String {
        let openPrefixes = ["<think", "<thin", "<thi", "<th", "<t", "<"]
        for prefix in openPrefixes {
            if content.hasSuffix(prefix) {
                return String(content.dropLast(prefix.count))
            }
        }
        let closePrefixes = ["</think", "</thin", "</thi", "</th", "</t", "</", "<"]
        for prefix in closePrefixes {
            if content.hasSuffix(prefix) {
                return String(content.dropLast(prefix.count))
            }
        }
        return content
    }

    /// Internal: split fence-delimited content into `.inline` / `.code` segments only.
    /// Does NOT understand `<think>` blocks — the top-level parser handles that first.
    private static func parseFences(_ content: String) -> [MessageSegment] {
        let lines = content.components(separatedBy: "\n")
        var segments: [MessageSegment] = []
        var inlineBuffer: [String] = []
        var codeBuffer: [String] = []
        var inCode = false
        var codeLanguage: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    // Close current code block
                    segments.append(.code(language: codeLanguage, body: codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                    codeLanguage = nil
                    inCode = false
                } else {
                    // Flush inline first
                    if !inlineBuffer.isEmpty {
                        let joined = inlineBuffer.joined(separator: "\n")
                        if !joined.isEmpty {
                            segments.append(.inline(joined))
                        }
                        inlineBuffer.removeAll()
                    }
                    // Open new code block — capture info string
                    let info = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    codeLanguage = info.isEmpty ? nil : info
                    inCode = true
                }
                continue
            }

            if inCode {
                codeBuffer.append(line)
            } else {
                inlineBuffer.append(line)
            }
        }

        // Flush whatever's left
        if inCode {
            // Unclosed fence — treat trailing text as a code block anyway so the user sees it
            segments.append(.code(language: codeLanguage, body: codeBuffer.joined(separator: "\n")))
        } else if !inlineBuffer.isEmpty {
            let joined = inlineBuffer.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.inline(joined))
            }
        }

        return segments
    }
}
