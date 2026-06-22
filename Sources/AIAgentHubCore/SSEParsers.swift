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
            .flatMap { line -> [ChatStreamEvent] in
                guard line.hasPrefix("data:") else {
                    return []
                }
                let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" {
                    return [.completed]
                }
                guard let data = payload.data(using: .utf8),
                      let envelope = try? JSONDecoder().decode(OpenAIStreamEnvelope.self, from: data) else {
                    return []
                }

                var events: [ChatStreamEvent] = []
                if let content = envelope.choices.first?.delta.content, !content.isEmpty {
                    events.append(.token(content))
                }

                if let call = envelope.choices.first?.delta.toolCalls?.first {
                    events.append(
                        .toolCall(
                            ToolCallRequest(
                                id: call.id ?? "",
                                name: call.function?.name ?? "",
                                argumentsJSON: call.function?.arguments ?? ""
                            )
                        )
                    )
                }

                // OpenAI ships usage in the final chunk (with `stream_options: { include_usage: true }`)
                // as a top-level `usage` field — choices array is empty at that point.
                if let usage = envelope.usage {
                    events.append(
                        .usage(
                            TokenUsage(
                                promptTokens: usage.promptTokens ?? 0,
                                completionTokens: usage.completionTokens ?? 0
                            )
                        )
                    )
                }

                return events
            }
    }
}

public struct ClaudeSSEParser: ChatStreamParser {
    public init() {}

    public func parse(_ data: Data) throws -> [ChatStreamEvent] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SSEParserError.invalidUTF8
        }

        // Claude folds prompt token count into message_start, then completion tokens land
        // in message_delta. We assemble them into a single TokenUsage and emit when both are
        // known (or one is known at message_stop, defaulting the missing side to 0).
        var promptTokens = 0
        var completionTokens = 0
        var sawUsage = false
        var events: [ChatStreamEvent] = []

        for block in text.components(separatedBy: "\n\n") {
            for event in parseEventBlock(block, prompt: &promptTokens, completion: &completionTokens, sawUsage: &sawUsage) {
                events.append(event)
            }
        }

        if sawUsage {
            // Emit a final usage summary so the orchestrator records it once per stream rather
            // than dribbling partial deltas. Insert just before the final .completed event if any.
            let summary = ChatStreamEvent.usage(
                TokenUsage(promptTokens: promptTokens, completionTokens: completionTokens)
            )
            if let idx = events.lastIndex(of: .completed) {
                events.insert(summary, at: idx)
            } else {
                events.append(summary)
            }
        }

        return events
    }

    private func parseEventBlock(
        _ block: String,
        prompt: inout Int,
        completion: inout Int,
        sawUsage: inout Bool
    ) -> [ChatStreamEvent] {
        let dataLine = block
            .split(separator: "\n")
            .first { $0.hasPrefix("data:") }

        guard let dataLine else {
            return []
        }

        let payload = dataLine.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ClaudeStreamEnvelope.self, from: data) else {
            return []
        }

        if envelope.type == "message_stop" {
            return [.completed]
        }

        if let usage = envelope.message?.usage {
            sawUsage = true
            prompt = usage.inputTokens ?? prompt
            // message_start sometimes carries an initial output_tokens count too.
            completion = usage.outputTokens ?? completion
        }

        if let usage = envelope.usage {
            sawUsage = true
            if let output = usage.outputTokens {
                completion = output
            }
            if let input = usage.inputTokens {
                prompt = input
            }
        }

        if let toolUse = envelope.contentBlock?.toolUse {
            return [.toolCall(toolUse)]
        }

        if let text = envelope.delta?.text, !text.isEmpty {
            return [.token(text)]
        }

        return []
    }
}

private struct OpenAIStreamEnvelope: Decodable {
    var choices: [Choice]
    var usage: Usage?

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

    struct Usage: Decodable {
        var promptTokens: Int?
        var completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
}

private struct ClaudeStreamEnvelope: Decodable {
    var type: String
    var delta: Delta?
    var contentBlock: ContentBlock?
    var message: Message?
    var usage: Usage?

    enum CodingKeys: String, CodingKey {
        case type
        case delta
        case contentBlock = "content_block"
        case message
        case usage
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

    struct Message: Decodable {
        var usage: Usage?
    }

    struct Usage: Decodable {
        var inputTokens: Int?
        var outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
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
