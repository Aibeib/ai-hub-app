import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AIHTTPClientError: Error, Equatable {
    case missingEndpoint
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int)
}

public protocol AIHTTPClient: Sendable {
    func bytes(for request: URLRequest) async throws -> AsyncThrowingStream<Data, Error>
}

public struct URLSessionAIHTTPClient: AIHTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func bytes(for request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIHTTPClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIHTTPClientError.httpStatus(httpResponse.statusCode)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        if let data = "\(line)\n\n".data(using: .utf8) {
                            continuation.yield(data)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

public final class ProviderAIService: AIService, @unchecked Sendable {
    private let client: any AIHTTPClient
    private let parser: any ChatStreamParser
    private let requestBuilder: any ProviderRequestBuilder

    public init(
        client: any AIHTTPClient,
        parser: any ChatStreamParser,
        requestBuilder: any ProviderRequestBuilder
    ) {
        self.client = client
        self.parser = parser
        self.requestBuilder = requestBuilder
    }

    public func streamChat(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let urlRequest = try requestBuilder.build(request)
                    let dataStream = try await client.bytes(for: urlRequest)

                    for try await chunk in dataStream {
                        for event in try parser.parse(chunk) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

public protocol ProviderRequestBuilder: Sendable {
    func build(_ request: ChatRequest) throws -> URLRequest
}

public struct OpenAICompatibleRequestBuilder: ProviderRequestBuilder {
    public init() {}

    public func build(_ request: ChatRequest) throws -> URLRequest {
        guard let endpoint = request.model.endpoint else {
            throw AIHTTPClientError.missingEndpoint
        }
        guard let apiKey = request.model.apiKey, !apiKey.isEmpty else {
            throw AIHTTPClientError.missingAPIKey
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 15
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(
            OpenAICompatibleRequestBody(
                model: request.model.modelName,
                messages: request.messages.map {
                    OpenAICompatibleRequestBody.Message(role: $0.role.rawValue, content: $0.content)
                },
                temperature: request.temperature,
                maxTokens: request.maxTokens,
                stream: true,
                tools: request.tools.map(OpenAICompatibleRequestBody.Tool.init(definition:))
            )
        )
        return urlRequest
    }
}

public struct ClaudeRequestBuilder: ProviderRequestBuilder {
    public init() {}

    public func build(_ request: ChatRequest) throws -> URLRequest {
        guard let endpoint = request.model.endpoint else {
            throw AIHTTPClientError.missingEndpoint
        }
        guard let apiKey = request.model.apiKey, !apiKey.isEmpty else {
            throw AIHTTPClientError.missingAPIKey
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 15
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(
            ClaudeRequestBody(
                model: request.model.modelName,
                messages: request.messages
                    .filter { $0.role != .system }
                    .map { ClaudeRequestBody.Message(role: $0.role.rawValue, content: $0.content) },
                maxTokens: request.maxTokens,
                temperature: request.temperature,
                stream: true,
                tools: request.tools.map(ClaudeRequestBody.Tool.init(definition:))
            )
        )
        return urlRequest
    }
}

public enum AIServiceFactory {
    public static func make(provider: ModelProvider, client: any AIHTTPClient = URLSessionAIHTTPClient()) -> any AIService {
        switch provider {
        case .openai, .deepseek:
            ProviderAIService(
                client: client,
                parser: OpenAICompatibleSSEParser(),
                requestBuilder: OpenAICompatibleRequestBuilder()
            )
        case .anthropic:
            ProviderAIService(
                client: client,
                parser: ClaudeSSEParser(),
                requestBuilder: ClaudeRequestBuilder()
            )
        case .apple:
            UnavailableAIService(reason: "Apple Foundation Models require iOS 26 or macOS 26.")
        }
    }
}

public struct UnavailableAIService: AIService {
    private let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func streamChat(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: AIServiceUnavailableError(reason: reason))
        }
    }
}

public struct AIServiceUnavailableError: Error, Equatable {
    public var reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

private struct OpenAICompatibleRequestBody: Encodable {
    var model: String
    var messages: [Message]
    var temperature: Double
    var maxTokens: Int
    var stream: Bool
    var streamOptions: StreamOptions
    var tools: [Tool]

    init(
        model: String,
        messages: [Message],
        temperature: Double,
        maxTokens: Int,
        stream: Bool,
        tools: [Tool]
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.stream = stream
        // Opt into the OpenAI usage chunk; DeepSeek mirrors the same field and is harmless
        // for other compatible providers — unknown fields are ignored on the server side.
        self.streamOptions = StreamOptions(includeUsage: true)
        self.tools = tools
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case streamOptions = "stream_options"
        case tools
    }

    struct StreamOptions: Encodable {
        var includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    struct Message: Encodable {
        var role: String
        var content: String
    }

    struct Tool: Encodable {
        var type = "function"
        var function: Function

        init(definition: ToolDefinition) {
            function = Function(definition: definition)
        }

        struct Function: Encodable {
            var name: String
            var description: String
            var parameters: ToolJSONSchema

            init(definition: ToolDefinition) {
                name = definition.name
                description = definition.description
                parameters = ToolJSONSchema(definition: definition)
            }
        }
    }
}

private struct ClaudeRequestBody: Encodable {
    var model: String
    var messages: [Message]
    var maxTokens: Int
    var temperature: Double
    var stream: Bool
    var tools: [Tool]

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case stream
        case tools
    }

    struct Message: Encodable {
        var role: String
        var content: String
    }

    struct Tool: Encodable {
        var name: String
        var description: String
        var inputSchema: ToolJSONSchema

        enum CodingKeys: String, CodingKey {
            case name
            case description
            case inputSchema = "input_schema"
        }

        init(definition: ToolDefinition) {
            name = definition.name
            description = definition.description
            inputSchema = ToolJSONSchema(definition: definition)
        }
    }
}

private struct ToolJSONSchema: Encodable {
    var type = "object"
    var properties: [String: Property]
    var required: [String]

    init(definition: ToolDefinition) {
        properties = Dictionary(uniqueKeysWithValues: definition.parameters.map { parameter in
            (parameter.name, Property(type: parameter.type.jsonSchemaType))
        })
        required = definition.parameters.filter(\.isRequired).map(\.name)
    }

    struct Property: Encodable {
        var type: String
    }
}

private extension ToolParameterType {
    var jsonSchemaType: String {
        switch self {
        case .string:
            "string"
        case .number:
            "number"
        case .boolean:
            "boolean"
        case .object:
            "object"
        }
    }
}
