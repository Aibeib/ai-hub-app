import Foundation

public enum SSEParserError: Error, Equatable {
    case invalidUTF8
}

public protocol ChatStreamParser: Sendable {
    func parse(_ data: Data) throws -> [ChatStreamEvent]
}

public struct OpenAICompatibleSSEParser: ChatStreamParser {
    public init() {}

    public func parse(_ data: Data) throws -> [ChatStreamEvent] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SSEParserError.invalidUTF8
        }

        return text
            .components(separatedBy: "\n\n")
            .flatMap(parseEventBlock)
    }

    private func parseEventBlock(_ block: String) -> [ChatStreamEvent] {
        block
            .split(separator: "\n")
            .compactMap { line -> ChatStreamEvent? in
                guard line.hasPrefix("data:") else {
                    return nil
                }
                let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" {
                    return .completed
                }
                guard let data = payload.data(using: .utf8),
                      let envelope = try? JSONDecoder().decode(OpenAIStreamEnvelope.self, from: data) else {
                    return nil
                }

                if let content = envelope.choices.first?.delta.content, !content.isEmpty {
                    return .token(content)
                }

                if let call = envelope.choices.first?.delta.toolCalls?.first {
                    return .toolCall(
                        ToolCallRequest(
                            id: call.id ?? "",
                            name: call.function?.name ?? "",
                            argumentsJSON: call.function?.arguments ?? ""
                        )
                    )
                }

                return nil
            }
    }
}

public struct ClaudeSSEParser: ChatStreamParser {
    public init() {}

    public func parse(_ data: Data) throws -> [ChatStreamEvent] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SSEParserError.invalidUTF8
        }

        return text
            .components(separatedBy: "\n\n")
            .compactMap(parseEventBlock)
    }

    private func parseEventBlock(_ block: String) -> ChatStreamEvent? {
        let dataLine = block
            .split(separator: "\n")
            .first { $0.hasPrefix("data:") }

        guard let dataLine else {
            return nil
        }

        let payload = dataLine.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ClaudeStreamEnvelope.self, from: data) else {
            return nil
        }

        if envelope.type == "message_stop" {
            return .completed
        }

        if let text = envelope.delta?.text, !text.isEmpty {
            return .token(text)
        }

        return nil
    }
}

private struct OpenAIStreamEnvelope: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var delta: Delta
    }

    struct Delta: Decodable {
        var content: String?
        var toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCall: Decodable {
        var id: String?
        var function: Function?
    }

    struct Function: Decodable {
        var name: String?
        var arguments: String?
    }
}

private struct ClaudeStreamEnvelope: Decodable {
    var type: String
    var delta: Delta?

    struct Delta: Decodable {
        var type: String?
        var text: String?
    }
}

