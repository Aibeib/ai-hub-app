import AIAgentHubCore
import Foundation

@main
struct ValidationRunner {
    static func main() async {
        do {
            try validatePrivacyRedactor()
            try await validateToolRegistry()
            try validateSSEParsers()
            try validateSecretStore()
            try validateRepositories()
            try await validateChatOrchestrator()
            print("AIAgentHubCoreValidation: all checks passed")
        } catch {
            fputs("AIAgentHubCoreValidation failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func validatePrivacyRedactor() throws {
        let redactor = PrivacyRedactor(deviceNames: ["Alice-MacBook"])
        let input = "Send /Users/alice/Documents/report.md from Alice-MacBook to me@example.com or 13812345678."
        let output = redactor.redact(input)

        try require(!output.contains("/Users/alice/Documents/report.md"), "path should be masked")
        try require(!output.contains("Alice-MacBook"), "device name should be masked")
        try require(!output.contains("me@example.com"), "email should be masked")
        try require(!output.contains("13812345678"), "phone should be masked")
        try require(output.contains("[local-path]"), "path marker missing")
        try require(output.contains("[device-name]"), "device marker missing")
        try require(output.contains("[email]"), "email marker missing")
        try require(output.contains("[phone]"), "phone marker missing")
    }

    private static func validateToolRegistry() async throws {
        let lowRiskAuditStore = InMemoryAuditLogStore()
        let lowRiskRegistry = ToolRegistry(
            tools: [ValidationEchoTool()],
            auditStore: lowRiskAuditStore,
            authorization: StaticToolAuthorization(decision: .cancelled)
        )

        let result = try await lowRiskRegistry.execute(
            toolName: "echo",
            arguments: ["text": .string("hello")],
            sessionId: UUID()
        )

        try require(result.displayText == "hello", "echo result mismatch")
        try require(lowRiskAuditStore.entries.count == 1, "low risk audit entry missing")
        try require(lowRiskAuditStore.entries[0].decision == .approved, "low risk should auto approve")
        try require(lowRiskAuditStore.entries[0].riskLevel == .low, "low risk audit mismatch")

        let highRiskAuditStore = InMemoryAuditLogStore()
        let highRiskRegistry = ToolRegistry(
            tools: [ValidationDangerousTool()],
            auditStore: highRiskAuditStore,
            authorization: StaticToolAuthorization(decision: .cancelled)
        )

        do {
            _ = try await highRiskRegistry.execute(
                toolName: "dangerous",
                arguments: [:],
                sessionId: UUID()
            )
            throw ValidationError("high risk cancellation did not throw")
        } catch ToolExecutionError.authorizationCancelled {
            try require(highRiskAuditStore.entries.count == 1, "high risk audit entry missing")
            try require(highRiskAuditStore.entries[0].decision == .cancelled, "high risk cancellation not audited")
            try require(highRiskAuditStore.entries[0].riskLevel == .high, "high risk audit mismatch")
        }
    }

    private static func validateSSEParsers() throws {
        let openAIPayload = """
        data: {"choices":[{"delta":{"content":"Hel"}}]}

        data: {"choices":[{"delta":{"content":"lo"}}]}

        data: [DONE]

        """
        let openAIEvents = try OpenAICompatibleSSEParser().parse(openAIPayload.data(using: .utf8)!)
        try require(openAIEvents == [.token("Hel"), .token("lo"), .completed], "OpenAI SSE parse mismatch")

        let claudePayload = """
        event: content_block_delta
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        let claudeEvents = try ClaudeSSEParser().parse(claudePayload.data(using: .utf8)!)
        try require(claudeEvents == [.token("Hi"), .completed], "Claude SSE parse mismatch")
    }

    private static func validateSecretStore() throws {
        let store = KeyValueSecretStore()
        try store.save("sk-test", for: "openai")
        let savedSecret = try store.read("openai")
        try require(savedSecret == "sk-test", "secret read mismatch")
        try store.delete("openai")
        let deletedSecret = try store.read("openai")
        try require(deletedSecret == nil, "secret delete failed")
    }

    private static func validateRepositories() throws {
        let clock = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        let repository = InMemoryChatRepository(clock: clock)
        let session = repository.createSession(title: "Planning", modelConfigId: nil)
        let message = repository.appendMessage(
            ChatMessageDTO(role: .user, content: "Hello"),
            to: session.id
        )

        try require(repository.messages(for: session.id) == [message], "message append failed")
        repository.softDeleteSession(session.id)
        try require(repository.sessions(includeDeleted: false).isEmpty, "deleted session should be hidden")
        try require(repository.sessions(includeDeleted: true).first?.deleteExpireAt != nil, "delete expiry missing")
    }

    private static func validateChatOrchestrator() async throws {
        let repository = InMemoryChatRepository()
        let session = repository.createSession(title: "Chat", modelConfigId: nil)
        let model = ResolvedModelConfig(
            id: UUID(),
            provider: .openai,
            name: "Test",
            modelName: "gpt-test",
            endpoint: URL(string: "https://example.com"),
            apiKey: "sk-test",
            temperature: 0.7,
            maxTokens: 100
        )
        let orchestrator = ChatOrchestrator(
            repository: repository,
            aiService: StubAIService(events: [.token("Hi"), .token("!"), .completed]),
            redactor: PrivacyRedactor(deviceNames: ["Alice-MacBook"]),
            contextBuilder: ContextBuilder(maxCharacters: 500)
        )

        let response = try await orchestrator.sendUserMessage(
            "Hello from /Users/alice/secret.txt",
            in: session.id,
            using: model
        )

        try require(response == "Hi!", "chat response mismatch")
        let messages = repository.messages(for: session.id)
        try require(messages.count == 2, "chat should persist user and assistant messages")
        try require(messages[0].content.contains("[local-path]"), "user message should be redacted")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw ValidationError(message)
        }
    }
}

private struct ValidationError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct ValidationEchoTool: Tool {
    let definition = ToolDefinition(
        name: "echo",
        description: "Echoes text.",
        parameters: [
            ToolParameter(name: "text", type: .string, isRequired: true)
        ]
    )
    let riskLevel = ToolRiskLevel.low

    func execute(arguments: [String: ToolArgument]) async throws -> ToolResult {
        guard case let .string(text) = arguments["text"] else {
            throw ToolExecutionError.invalidArguments("text is required")
        }
        return ToolResult(displayText: text)
    }
}

private struct ValidationDangerousTool: Tool {
    let definition = ToolDefinition(name: "dangerous", description: "A high risk action.", parameters: [])
    let riskLevel = ToolRiskLevel.high

    func execute(arguments: [String: ToolArgument]) async throws -> ToolResult {
        ToolResult(displayText: "should not execute")
    }
}
