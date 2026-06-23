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

    public var rawText: String {
        switch self {
        case let .inline(text):
            text
        case let .code(_, body):
            body
        }
    }
}

public enum MessageSegmentParser {
    /// Split a message into alternating inline / code segments.
    ///
    /// Splits on triple-backtick fences at the start of a line. Tolerates missing closing
    /// fences (treats the rest of the message as one open code block).
    public static func parse(_ content: String) -> [MessageSegment] {
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
