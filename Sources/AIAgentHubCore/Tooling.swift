import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ToolRiskLevel: String, Codable, Equatable, Sendable {
    case low
    case high
}

public enum ToolParameterType: String, Codable, Equatable, Sendable {
    case string
    case number
    case boolean
    case object
}

public struct ToolParameter: Codable, Equatable, Sendable {
    public var name: String
    public var type: ToolParameterType
    public var isRequired: Bool

    public init(name: String, type: ToolParameterType, isRequired: Bool) {
        self.name = name
        self.type = type
        self.isRequired = isRequired
    }
}

public struct ToolDefinition: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var parameters: [ToolParameter]

    public init(name: String, description: String, parameters: [ToolParameter]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public enum ToolArgument: Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: ToolArgument])
}

public enum ToolArgumentDecoderError: Error, Equatable {
    case invalidJSON
    case unsupportedValue(String)
}

public enum ToolArgumentDecoder {
    public static func decode(_ json: String) throws -> [String: ToolArgument] {
        guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [:]
        }
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolArgumentDecoderError.invalidJSON
        }
        return try object.mapValues(convert)
    }

    private static func convert(_ value: Any) throws -> ToolArgument {
        switch value {
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            return .number(number.doubleValue)
        case let object as [String: Any]:
            return .object(try object.mapValues(convert))
        default:
            throw ToolArgumentDecoderError.unsupportedValue(String(describing: value))
        }
    }
}

public struct ToolResult: Equatable, Sendable {
    public var displayText: String
    public var metadata: [String: String]

    public init(displayText: String, metadata: [String: String] = [:]) {
        self.displayText = displayText
        self.metadata = metadata
    }
}

public enum ToolExecutionError: Error, Equatable {
    case toolNotFound(String)
    case invalidArguments(String)
    case authorizationCancelled
}

public protocol Tool: Sendable {
    var definition: ToolDefinition { get }
    var riskLevel: ToolRiskLevel { get }
    func execute(arguments: [String: ToolArgument]) async throws -> ToolResult
}

public enum ToolAuthorizationDecision: String, Codable, Equatable, Sendable {
    case approved
    case cancelled
}

public protocol ToolAuthorization: Sendable {
    func authorize(tool: ToolDefinition, riskLevel: ToolRiskLevel, arguments: [String: ToolArgument]) async -> ToolAuthorizationDecision
}

public struct StaticToolAuthorization: ToolAuthorization {
    private let decision: ToolAuthorizationDecision

    public init(decision: ToolAuthorizationDecision) {
        self.decision = decision
    }

    public func authorize(
        tool: ToolDefinition,
        riskLevel: ToolRiskLevel,
        arguments: [String: ToolArgument]
    ) async -> ToolAuthorizationDecision {
        decision
    }
}

public struct ToolExecutionLogEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var sessionId: UUID
    public var toolName: String
    public var riskLevel: ToolRiskLevel
    public var decision: ToolAuthorizationDecision
    public var summary: String
    public var createdAt: Date
    public var expiresAt: Date

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        toolName: String,
        riskLevel: ToolRiskLevel,
        decision: ToolAuthorizationDecision,
        summary: String,
        createdAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(30 * 24 * 60 * 60)
    ) {
        self.id = id
        self.sessionId = sessionId
        self.toolName = toolName
        self.riskLevel = riskLevel
        self.decision = decision
        self.summary = summary
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

public protocol AuditLogStore: Sendable {
    func append(_ entry: ToolExecutionLogEntry) async
    func clearExpired(now: Date) async
    func clearAll() async
}

public final class InMemoryAuditLogStore: AuditLogStore, @unchecked Sendable {
    private var storage: [ToolExecutionLogEntry]
    private let lock = NSLock()

    public init(entries: [ToolExecutionLogEntry] = []) {
        self.storage = entries
    }

    public var entries: [ToolExecutionLogEntry] {
        lock.withLock {
            storage
        }
    }

    public func append(_ entry: ToolExecutionLogEntry) async {
        lock.withLock {
            storage.append(entry)
        }
    }

    public func clearExpired(now: Date) async {
        lock.withLock {
            storage.removeAll { $0.expiresAt <= now }
        }
    }

    public func clearAll() async {
        lock.withLock {
            storage.removeAll()
        }
    }
}

public final class ToolRegistry: @unchecked Sendable {
    private let tools: [String: any Tool]
    private let auditStore: any AuditLogStore
    private let authorization: any ToolAuthorization
    private let retentionDaysProvider: @Sendable () -> Int
    private let clock: any Clock

    public init(
        tools: [any Tool],
        auditStore: any AuditLogStore,
        authorization: any ToolAuthorization,
        retentionDays: Int = 30,
        clock: any Clock = SystemClock()
    ) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.definition.name, $0) })
        self.auditStore = auditStore
        self.authorization = authorization
        let frozen = max(1, retentionDays)
        self.retentionDaysProvider = { frozen }
        self.clock = clock
    }

    /// Variant that takes a live closure, so the retention window updates immediately when the
    /// user changes their privacy preference without rebuilding the registry.
    public init(
        tools: [any Tool],
        auditStore: any AuditLogStore,
        authorization: any ToolAuthorization,
        retentionDaysProvider: @escaping @Sendable () -> Int,
        clock: any Clock = SystemClock()
    ) {
        self.tools = Dictionary(uniqueKeysWithValues: tools.map { ($0.definition.name, $0) })
        self.auditStore = auditStore
        self.authorization = authorization
        self.retentionDaysProvider = retentionDaysProvider
        self.clock = clock
    }

    public var definitions: [ToolDefinition] {
        tools.values.map(\.definition).sorted { $0.name < $1.name }
    }

    public func execute(
        toolName: String,
        arguments: [String: ToolArgument],
        sessionId: UUID
    ) async throws -> ToolResult {
        guard let tool = tools[toolName] else {
            throw ToolExecutionError.toolNotFound(toolName)
        }

        let decision: ToolAuthorizationDecision
        if tool.riskLevel == .high {
            decision = await authorization.authorize(
                tool: tool.definition,
                riskLevel: tool.riskLevel,
                arguments: arguments
            )
        } else {
            decision = .approved
        }

        let now = clock.now
        let retentionDays = max(1, retentionDaysProvider())
        let expiresAt = now.addingTimeInterval(TimeInterval(retentionDays) * 86_400)

        await auditStore.append(
            ToolExecutionLogEntry(
                sessionId: sessionId,
                toolName: toolName,
                riskLevel: tool.riskLevel,
                decision: decision,
                summary: "\(tool.definition.name): \(decision.rawValue)",
                createdAt: now,
                expiresAt: expiresAt
            )
        )

        guard decision == .approved else {
            throw ToolExecutionError.authorizationCancelled
        }

        return try await tool.execute(arguments: arguments)
    }
}

public struct TextSummaryTool: Tool {
    public let definition = ToolDefinition(
        name: "summarize_text",
        description: "Summarizes app-provided text without accessing external files.",
        parameters: [
            ToolParameter(name: "text", type: .string, isRequired: true)
        ]
    )
    public let riskLevel = ToolRiskLevel.low

    public init() {}

    public func execute(arguments: [String: ToolArgument]) async throws -> ToolResult {
        guard case let .string(text) = arguments["text"] else {
            throw ToolExecutionError.invalidArguments("text is required")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = trimmed.count <= 180 ? trimmed : String(trimmed.prefix(177)) + "..."
        return ToolResult(displayText: summary)
    }
}

public struct WebFetchResult: Equatable, Sendable {
    public var url: URL
    public var title: String?
    public var text: String

    public init(url: URL, title: String? = nil, text: String) {
        self.url = url
        self.title = title
        self.text = text
    }
}

public protocol WebContentClient: Sendable {
    func fetch(url: URL) async throws -> WebFetchResult
}

public struct URLSessionWebContentClient: WebContentClient {
    private let session: URLSession
    private let maxBytes: Int

    public init(session: URLSession = .shared, maxBytes: Int = 512_000) {
        self.session = session
        self.maxBytes = maxBytes
    }

    public func fetch(url: URL) async throws -> WebFetchResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (compatible; AI-Agent-Hub/1.0)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ToolExecutionError.invalidArguments("URL returned a non-success HTTP response.")
        }

        let limited = data.prefix(maxBytes)
        guard let html = String(data: Data(limited), encoding: .utf8)
            ?? String(data: Data(limited), encoding: .isoLatin1) else {
            throw ToolExecutionError.invalidArguments("URL did not return readable text.")
        }

        return WebFetchResult(
            url: httpResponse.url ?? url,
            title: Self.extractTitle(from: html),
            text: Self.extractReadableText(from: html)
        )
    }

    private static func extractTitle(from html: String) -> String? {
        guard let range = html.range(
            of: #"<title[^>]*>(.*?)</title>"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }
        let raw = String(html[range])
            .replacingOccurrences(
                of: #"<\/?title[^>]*>"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        let title = decodeCommonHTMLEntities(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func extractReadableText(from html: String) -> String {
        let withoutScripts = html
            .replacingOccurrences(
                of: #"<script[\s\S]*?</script>"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"<style[\s\S]*?</style>"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        let withoutTags = withoutScripts.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let decoded = decodeCommonHTMLEntities(withoutTags)
        return decoded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func decodeCommonHTMLEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

public struct WebFetchTool: Tool {
    public let definition = ToolDefinition(
        name: "web_fetch",
        description: "Fetches a public http(s) URL and returns readable page text for current information. Use this for any model/provider when the user asks for current web content.",
        parameters: [
            ToolParameter(name: "url", type: .string, isRequired: true)
        ]
    )
    public let riskLevel = ToolRiskLevel.low

    private let client: any WebContentClient
    private let maxCharacters: Int

    public init(client: any WebContentClient = URLSessionWebContentClient(), maxCharacters: Int = 6_000) {
        self.client = client
        self.maxCharacters = maxCharacters
    }

    public func execute(arguments: [String: ToolArgument]) async throws -> ToolResult {
        // Bad inputs (empty url, non-http scheme) are common when the model invents a tool call
        // for trivia like "what's today's date". Throwing here would surface a scary alert to
        // the user; instead we return a ToolResult so the model can recover on the next turn.
        guard case let .string(rawURL) = arguments["url"] else {
            return ToolResult(
                displayText: "web_fetch needs a `url` parameter — please call it with a full http(s) URL like https://example.com."
            )
        }
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return ToolResult(
                displayText: "web_fetch requires an http(s) URL. Got: \"\(trimmed)\". Please retry with the full URL."
            )
        }

        let result = try await client.fetch(url: url)
        let trimmedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let limitedText = trimmedText.count <= maxCharacters
            ? trimmedText
            : String(trimmedText.prefix(maxCharacters)) + "..."
        let titleLine = result.title.map { "Title: \($0)\n" } ?? ""
        return ToolResult(
            displayText: "\(titleLine)URL: \(result.url.absoluteString)\n\n\(limitedText)",
            metadata: ["url": result.url.absoluteString]
        )
    }
}

public struct StubWebContentClient: WebContentClient {
    private let result: WebFetchResult

    public init(result: WebFetchResult) {
        self.result = result
    }

    public func fetch(url: URL) async throws -> WebFetchResult {
        result
    }
}
