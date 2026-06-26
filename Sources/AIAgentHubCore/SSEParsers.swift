import Foundation

public enum SSEParserError: Error, Equatable {
    case invalidUTF8
}

/// Streaming parser. `parse` is called once per SSE event the transport receives, and
/// implementations may accumulate state across calls — both OpenAI and Anthropic split
/// streaming tool-call arguments into many micro-chunks, and we have to stitch them back
/// together before handing a `.toolCall` event up to the orchestrator.
///
/// Implementations are expected to be created fresh per chat request (see
/// `AIServiceFactory.make`) so cross-request state contamination is impossible.
public protocol ChatStreamParser: Sendable {
    func parse(_ data: Data) throws -> [ChatStreamEvent]
}

/// OpenAI-compatible parser (also used for DeepSeek and Volcengine — they share the
/// `chat/completions` SSE shape). Streaming tool calls are accumulated by `index` until
/// the model emits `finish_reason: "tool_calls"`, at which point the full ToolCallRequest
/// is flushed. Content tokens, usage, and stop reasons pass through immediately.
///
/// DeepSeek's reasoner models additionally stream a `reasoning_content` field per delta.
/// We wrap that in synthetic `<think>...</think>` markers (one open at first reasoning
/// delta, one close at the first non-reasoning content delta) so the rest of the pipeline
/// — segment parser, transcript renderer — can treat it as a structured chain-of-thought
/// block with no provider-specific code.
public final class OpenAICompatibleSSEParser: ChatStreamParser, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Int: PendingToolCall] = [:]
    /// Ordering bookkeeping: emit tool calls in the order their `index` was first seen.
    private var insertionOrder: [Int] = []
    /// Whether we've opened a `<think>` block that still needs closing. Used to wrap
    /// DeepSeek's `reasoning_content` deltas into a single thinking segment.
    private var thinkingOpen = false

    private struct PendingToolCall {
        var id: String
        var name: String
        var arguments: String
    }

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
                    // Flush any tool calls that were in flight without a finish_reason event
                    // (some Volcengine variants finish the stream without one). Use the
                    // lock-guarded helper to avoid duplicate emissions if `tool_calls` already
                    // flushed them. Also close any open thinking block so the segment parser
                    // doesn't treat the whole reply as in-progress reasoning.
                    let flushed = flushPendingCalls()
                    var tail: [ChatStreamEvent] = []
                    if thinkingOpen {
                        tail.append(.token("</think>\n\n"))
                        thinkingOpen = false
                    }
                    return tail + flushed + [.completed]
                }
                guard let data = payload.data(using: .utf8),
                      let envelope = try? JSONDecoder().decode(OpenAIStreamEnvelope.self, from: data) else {
                    return []
                }

                var events: [ChatStreamEvent] = []
                // DeepSeek reasoner / Volcengine reasoning models stream chain-of-thought as
                // `reasoning_content` deltas that arrive BEFORE any `content` deltas. We wrap
                // the whole reasoning run in `<think>...</think>` markers and pass them
                // through as normal tokens — the segment parser turns this into a collapsible
                // thinking card with no extra plumbing.
                let delta = envelope.choices.first?.delta
                if let reasoning = delta?.reasoningContent, !reasoning.isEmpty {
                    if !thinkingOpen {
                        events.append(.token("<think>"))
                        thinkingOpen = true
                    }
                    events.append(.token(reasoning))
                }
                if let content = delta?.content, !content.isEmpty {
                    if thinkingOpen {
                        events.append(.token("</think>\n\n"))
                        thinkingOpen = false
                    }
                    events.append(.token(content))
                }

                // Accumulate tool-call fragments. OpenAI sends the `id` and `function.name`
                // only on the first chunk for each tool index, then dribbles `arguments` as
                // raw JSON string fragments. Building one ToolCallRequest per delta (the old
                // behaviour) caused the orchestrator to execute the tool N times with
                // half-formed JSON, which is exactly the failure mode the user hit with the
                // `web_fetch requires an http(s) URL` alert.
                if let calls = envelope.choices.first?.delta.toolCalls {
                    accumulate(calls: calls)
                }

                // OpenAI sends finish_reason in the chunk where the model stops; on the very
                // last chunk choices is empty and only usage is present, so we read it from
                // whichever choice exists.
                let finishReason = envelope.choices.first?.finishReason
                if finishReason == "tool_calls" {
                    events.append(contentsOf: flushPendingCalls())
                }

                if let reason = StopReason.fromOpenAI(finishReason) {
                    events.append(.stop(reason))
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

    private func accumulate(calls: [OpenAIStreamEnvelope.ToolCall]) {
        lock.lock()
        defer { lock.unlock() }
        for call in calls {
            let index = call.index ?? 0
            var slot = pending[index] ?? PendingToolCall(id: "", name: "", arguments: "")
            if slot.id.isEmpty, let id = call.id, !id.isEmpty {
                slot.id = id
            }
            if slot.name.isEmpty, let name = call.function?.name, !name.isEmpty {
                slot.name = name
            }
            if let fragment = call.function?.arguments {
                slot.arguments += fragment
            }
            if pending[index] == nil {
                insertionOrder.append(index)
            }
            pending[index] = slot
        }
    }

    private func flushPendingCalls() -> [ChatStreamEvent] {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else { return [] }
        var events: [ChatStreamEvent] = []
        for index in insertionOrder {
            guard let slot = pending[index] else { continue }
            // Skip empty placeholders — a model can theoretically open and abandon a tool
            // call index without ever sending a name.
            guard !slot.name.isEmpty else { continue }
            events.append(
                .toolCall(
                    ToolCallRequest(
                        id: slot.id,
                        name: slot.name,
                        argumentsJSON: slot.arguments.isEmpty ? "{}" : slot.arguments
                    )
                )
            )
        }
        pending.removeAll()
        insertionOrder.removeAll()
        return events
    }
}

/// Claude Messages SSE parser. Claude's streaming protocol carries `content_block_start`
/// followed by zero-or-more `input_json_delta` deltas, then `content_block_stop` per tool
/// call. We accumulate the JSON deltas keyed by content-block index and emit one
/// ToolCallRequest at stop.
///
/// Anthropic extended thinking models emit a separate `thinking` content block with
/// `thinking_delta` updates. We wrap those in `<think>...</think>` tokens just like the
/// OpenAI parser does for `reasoning_content`, so the rest of the pipeline only has to
/// understand one CoT format.
public final class ClaudeSSEParser: ChatStreamParser, @unchecked Sendable {
    private let lock = NSLock()
    private var pendingTools: [Int: PendingToolUse] = [:]
    private var thinkingBlocks: Set<Int> = []
    private var promptTokens = 0
    private var completionTokens = 0
    private var sawUsage = false

    private struct PendingToolUse {
        var id: String
        var name: String
        /// Either the inline `input` from `content_block_start` (rare), or accumulated
        /// `input_json_delta.partial_json` fragments.
        var argumentsJSON: String
    }

    public init() {}

    public func parse(_ data: Data) throws -> [ChatStreamEvent] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SSEParserError.invalidUTF8
        }

        var events: [ChatStreamEvent] = []
        for block in text.components(separatedBy: "\n\n") {
            events.append(contentsOf: parseEventBlock(block))
        }
        return events
    }

    private func parseEventBlock(_ block: String) -> [ChatStreamEvent] {
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

        var emitted: [ChatStreamEvent] = []

        switch envelope.type {
        case "message_start":
            if let usage = envelope.message?.usage {
                lock.lock()
                sawUsage = true
                promptTokens = usage.inputTokens ?? promptTokens
                completionTokens = usage.outputTokens ?? completionTokens
                lock.unlock()
            }

        case "content_block_start":
            // Begin tracking a tool_use block. Inline `input` (when present) becomes the
            // baseline; subsequent input_json_delta entries append to it.
            if envelope.contentBlock?.type == "tool_use",
               let id = envelope.contentBlock?.id,
               let name = envelope.contentBlock?.name {
                let initial = (try? envelope.contentBlock?.input?.jsonString()) ?? ""
                lock.lock()
                pendingTools[envelope.index ?? 0] = PendingToolUse(
                    id: id,
                    name: name,
                    argumentsJSON: initial == "{}" ? "" : initial
                )
                lock.unlock()
            }
            // Extended-thinking block — track the index so the matching deltas know to wrap
            // their content in `<think>` tokens.
            if envelope.contentBlock?.type == "thinking" {
                lock.lock()
                thinkingBlocks.insert(envelope.index ?? 0)
                lock.unlock()
                emitted.append(.token("<think>"))
            }

        case "content_block_delta":
            let idx = envelope.index ?? 0
            // Thinking delta — Anthropic sends these as `delta.type == "thinking_delta"`
            // with the chain-of-thought text in `delta.thinking`. Treat them like any other
            // streaming token, but they're already inside our synthetic `<think>` block.
            if let thinking = envelope.delta?.thinking, !thinking.isEmpty {
                emitted.append(.token(thinking))
            }
            if let text = envelope.delta?.text, !text.isEmpty {
                emitted.append(.token(text))
            }
            if let partial = envelope.delta?.partialJSON {
                lock.lock()
                if var slot = pendingTools[idx] {
                    slot.argumentsJSON += partial
                    pendingTools[idx] = slot
                }
                lock.unlock()
            }

        case "content_block_stop":
            let idx = envelope.index ?? 0
            lock.lock()
            let finished = pendingTools.removeValue(forKey: idx)
            let wasThinking = thinkingBlocks.remove(idx) != nil
            lock.unlock()
            if let finished {
                emitted.append(
                    .toolCall(
                        ToolCallRequest(
                            id: finished.id,
                            name: finished.name,
                            argumentsJSON: finished.argumentsJSON.isEmpty ? "{}" : finished.argumentsJSON
                        )
                    )
                )
            }
            if wasThinking {
                emitted.append(.token("</think>\n\n"))
            }

        case "message_delta":
            if let usage = envelope.usage {
                lock.lock()
                sawUsage = true
                if let output = usage.outputTokens { completionTokens = output }
                if let input = usage.inputTokens { promptTokens = input }
                lock.unlock()
            }
            if let stop = StopReason.fromClaude(envelope.delta?.stopReason) {
                emitted.append(.stop(stop))
            }

        case "message_stop":
            // Emit summary usage + completed sentinel. Snapshot under the lock so we don't
            // race with a future event landing on a different task.
            lock.lock()
            let hadUsage = sawUsage
            let prompt = promptTokens
            let completion = completionTokens
            lock.unlock()
            if hadUsage {
                emitted.append(.usage(TokenUsage(promptTokens: prompt, completionTokens: completion)))
            }
            emitted.append(.completed)

        default:
            break
        }

        return emitted
    }
}

private struct OpenAIStreamEnvelope: Decodable {
    var choices: [Choice]
    var usage: Usage?

    struct Choice: Decodable {
        var delta: Delta
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        var content: String?
        var reasoningContent: String?
        var toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case content
            // DeepSeek uses `reasoning_content`; some Volcengine reasoner variants use
            // `reasoning` instead. Decode both and prefer whichever is present.
            case reasoningContent = "reasoning_content"
            case reasoning
            case toolCalls = "tool_calls"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            content = try container.decodeIfPresent(String.self, forKey: .content)
            toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
            if let primary = try container.decodeIfPresent(String.self, forKey: .reasoningContent) {
                reasoningContent = primary
            } else {
                reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoning)
            }
        }
    }

    struct ToolCall: Decodable {
        /// OpenAI streams put the per-call index on the delta so we can stitch fragments
        /// back together. Older snapshots and a few compatible providers omit it on the
        /// first delta, so the parser falls back to 0 when missing.
        var index: Int?
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
    var index: Int?
    var delta: Delta?
    var contentBlock: ContentBlock?
    var message: Message?
    var usage: Usage?

    enum CodingKeys: String, CodingKey {
        case type
        case index
        case delta
        case contentBlock = "content_block"
        case message
        case usage
    }

    struct Delta: Decodable {
        var type: String?
        var text: String?
        var stopReason: String?
        var partialJSON: String?
        /// Extended-thinking text fragment. Anthropic emits these as
        /// `{"type":"thinking_delta","thinking":"..."}` inside a thinking content block.
        var thinking: String?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case stopReason = "stop_reason"
            case partialJSON = "partial_json"
            case thinking
        }
    }

    struct ContentBlock: Decodable {
        var type: String
        var id: String?
        var name: String?
        var input: JSONValue?
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
