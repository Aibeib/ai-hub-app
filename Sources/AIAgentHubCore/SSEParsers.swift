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

        if let toolUse = envelope.contentBlock?.toolUse {
            return .toolCall(toolUse)
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
    var contentBlock: ContentBlock?

    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case contentBlock = "content_block"
    }

    struct Delta: Decodable {
        var type: String?
        var text: String?
    }

    struct ContentBlock: Decodable {
        var type: String
        var id: String?
        var name: String?
        var input: JSONValue?

        var toolUse: ToolCallRequest? {
            guard type == "tool_use", let id, let name else {
                return nil
            }
            let argumentsJSON = (try? input?.jsonString()) ?? "{}"
            return ToolCallRequest(id: id, name: name, argumentsJSON: argumentsJSON)
        }
    }
}

private enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func jsonString() throws -> String {
        let object = foundationObject
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private var foundationObject: Any {
        switch self {
        case let .string(value):
            value
        case let .number(value):
            value
        case let .bool(value):
            value
        case let .object(value):
            value.mapValues(\.foundationObject)
        case let .array(value):
            value.map(\.foundationObject)
        case .null:
            NSNull()
        }
    }
}
