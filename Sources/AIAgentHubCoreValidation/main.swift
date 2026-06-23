import AIAgentHubCore
import Foundation

@main
struct ValidationRunner {
    static func main() async {
        do {
            try validatePrivacyRedactor()
            try await validateToolRegistry()
            try validateSSEParsers()
            try validateProviderToolSchemas()
            try validateSecretStore()
            try validateRepositories()
            try await validateModelConfigurationFlow()
            try await validateChatOrchestrator()
            try await validateToolCallingChatLoop()
            try await validateDeviceCoordinator()
            try await validateSandboxExecutor()
            try validateEncryptedTransport()
            try validateEncryptedRemoteTransportCodec()
            try await validateStreamingResponseBuffer()
            try validatePrivacyPreferences()
            try validateSessionMutationOperations()
            try await validateStreamingChatOrchestrator()
            try await validateThirdPartyPrivacyGate()
            try await validateRedactionOptOut()
            try await validateAutoTitling()
            try await validateRegenerate()
            try validateSessionTitleDeriver()
            try validateConversationExporter()
            try await validateTokenUsageTracking()
            try await validateMessageSearch()
            try await validateGenerationCancellation()
            try validateOpenAIUsageParsing()
            try validateClaudeUsageParsing()
            try await validateAuditRetentionFollowsPreference()
            try validateJSONExport()
            try await validateSystemPromptInjection()
            try validateMessageEditAndDeletion()
            try validateBranchSession()
            try validateStopReasonParsing()
            try validateLastSessionStore()
            try validateMessageSegmentParser()
            try validateContextBuilderTurnAware()
            try validateBookmarkToggle()
            try validateSlashCommandParser()
            try validateTokenEstimator()
            try validateRelativeTimeFormatter()
            try validateSessionDateGrouper()
            try validateErrorMessageMapper()
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

        let claudeToolPayload = """
        event: content_block_start
        data: {"type":"content_block_start","content_block":{"type":"tool_use","id":"toolu_1","name":"summarize_text","input":{"text":"hello"}}}

        """
        let claudeToolEvents = try ClaudeSSEParser().parse(claudeToolPayload.data(using: .utf8)!)
        try require(
            claudeToolEvents == [
                .toolCall(ToolCallRequest(id: "toolu_1", name: "summarize_text", argumentsJSON: #"{"text":"hello"}"#))
            ],
            "Claude tool use parse mismatch"
        )
    }

    private static func validateProviderToolSchemas() throws {
        let model = ResolvedModelConfig(
            id: UUID(),
            provider: .openai,
            name: "OpenAI",
            modelName: "gpt-test",
            endpoint: URL(string: "https://example.com"),
            apiKey: "sk-test",
            temperature: 0.7,
            maxTokens: 512
        )
        let tool = ToolDefinition(
            name: "summarize_text",
            description: "Summarizes text.",
            parameters: [
                ToolParameter(name: "text", type: .string, isRequired: true)
            ]
        )
        let request = ChatRequest(
            model: model,
            messages: [ChatMessageDTO(role: .user, content: "Hello")],
            tools: [tool],
            temperature: model.temperature,
            maxTokens: model.maxTokens
        )

        let openAIRequest = try OpenAICompatibleRequestBuilder().build(request)
        let openAIBody = try requireJSONObject(openAIRequest.httpBody)
        let openAITools = openAIBody["tools"] as? [[String: Any]]
        try require(openAITools?.first?["type"] as? String == "function", "OpenAI tool type missing")

        let claudeRequest = try ClaudeRequestBuilder().build(request)
        let claudeBody = try requireJSONObject(claudeRequest.httpBody)
        let claudeTools = claudeBody["tools"] as? [[String: Any]]
        try require(claudeTools?.first?["name"] as? String == "summarize_text", "Claude tool name missing")
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
        repository.clearAllSessions()
        try require(repository.sessions(includeDeleted: true).isEmpty, "clear all sessions failed")
    }

    private static func validateModelConfigurationFlow() async throws {
        let secrets = KeyValueSecretStore()
        let repository = InMemoryModelConfigRepository()
        let manager = ModelConfigurationManager(
            repository: repository,
            secretStore: secrets,
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        )

        let openAI = try manager.save(
            ModelConfigurationDraft(
                name: "OpenAI Work",
                provider: .openai,
                modelName: "gpt-4.1-mini",
                baseURL: nil,
                apiKey: "sk-openai",
                temperature: 0.5,
                maxTokens: 2_000,
                isDefault: true,
                isEnabled: true
            )
        )
        let disabledClaude = try manager.save(
            ModelConfigurationDraft(
                name: "Claude Disabled",
                provider: .anthropic,
                modelName: "claude-sonnet-4-5",
                baseURL: nil,
                apiKey: "sk-claude",
                temperature: 0.7,
                maxTokens: 4_000,
                isDefault: false,
                isEnabled: false
            )
        )

        try require(manager.enabledModels().map(\.id) == [openAI.id], "disabled models should not be enabled")
        try require(manager.defaultModel()?.id == openAI.id, "default model mismatch")

        let resolved = try manager.resolveDefaultModel()
        try require(resolved.id == openAI.id, "resolved model id mismatch")
        try require(resolved.apiKey == "sk-openai", "resolved API key mismatch")
        try require(resolved.endpoint == ModelProvider.openai.defaultBaseURL, "default endpoint mismatch")

        try manager.deleteModel(disabledClaude.id)
        try require(repository.all().count == 1, "delete should remove model config")

        let service = try manager.makeServiceForDefault(client: ValidationAIHTTPClient())
        let session = InMemoryChatRepository().createSession(title: "Provider", modelConfigId: openAI.id)
        let request = ChatRequest(
            model: resolved,
            messages: [ChatMessageDTO(role: .user, content: "Hello")],
            temperature: resolved.temperature,
            maxTokens: resolved.maxTokens
        )
        let events = try await awaitEvents(from: service.streamChat(request: request))
        try require(events == [.token("provider-ok"), .completed], "provider service resolver mismatch")
        try require(session.modelConfigId == openAI.id, "session should carry selected model")
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

    private static func validateToolCallingChatLoop() async throws {
        let repository = InMemoryChatRepository()
        let auditStore = InMemoryAuditLogStore()
        let toolRegistry = ToolRegistry(
            tools: [TextSummaryTool()],
            auditStore: auditStore,
            authorization: StaticToolAuthorization(decision: .approved)
        )
        let session = repository.createSession(title: "Tools", modelConfigId: nil)
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
            aiService: StubAIService(events: [
                .toolCall(
                    ToolCallRequest(
                        id: "call-1",
                        name: "summarize_text",
                        argumentsJSON: #"{"text":"This is a long internal note that should be summarized by the local tool."}"#
                    )
                ),
                .token("Summary ready."),
                .completed
            ]),
            redactor: PrivacyRedactor(),
            contextBuilder: ContextBuilder(maxCharacters: 500),
            toolRegistry: toolRegistry
        )

        let response = try await orchestrator.sendUserMessage(
            "Summarize the note",
            in: session.id,
            using: model,
            tools: toolRegistry.definitions
        )

        let messages = repository.messages(for: session.id)
        try require(response == "Summary ready.", "tool chat response mismatch")
        try require(messages.count == 3, "tool loop should persist user, tool, and assistant messages")
        try require(messages[1].role == .tool, "middle message should be tool result")
        try require(messages[1].content.contains("This is a long internal note"), "tool result should be persisted")
        try require(auditStore.entries.count == 1, "tool execution should be audited")
        await auditStore.clearAll()
        try require(auditStore.entries.isEmpty, "tool audit clear failed")
    }

    private static func validateDeviceCoordinator() async throws {
        let repository = InMemoryBoundDeviceRepository()
        let logStore = InMemoryRemoteCommandLogStore()
        let discovered = DiscoveredDevice(name: "Work Mac", host: "192.168.1.10", port: 41731, kind: .mac)
        let coordinator = DeviceCoordinator(
            connectionService: MockDeviceConnectionService(devices: [discovered]),
            repository: repository,
            authorization: StaticRemoteCommandAuthorization(decision: .cancelled),
            logStore: logStore
        )

        let manual = coordinator.addManualMac(name: "", host: "192.168.1.20")
        try require(manual.name == "Manual Mac", "manual device should use fallback name")
        try require(repository.all().count == 1, "manual device should be stored")

        let paired = try await coordinator.pair(discovered)
        try require(repository.all().map(\.id).contains(paired.id), "paired device should be stored")

        let lowRisk = RemoteCommand(instruction: "Create a draft report", risk: .low)
        let lowRiskResult = try await coordinator.send(lowRisk, to: paired)
        try require(lowRiskResult.commandId == lowRisk.id, "low risk remote result mismatch")

        let highRisk = RemoteCommand(instruction: "Run code", risk: .high)
        do {
            _ = try await coordinator.send(highRisk, to: paired)
            throw ValidationError("cancelled high risk command did not throw")
        } catch DeviceCoordinatorError.authorizationCancelled {
            try require(logStore.entries.count == 2, "remote command logs missing")
            try require(logStore.entries.last?.decision == .cancelled, "cancelled remote command not audited")
            await logStore.clearAll()
            try require(logStore.entries.isEmpty, "remote command log clear failed")
        }
    }

    private static func validateSandboxExecutor() async throws {
        let command = SandboxCommand(
            instruction: "Create a sandbox draft",
            risk: .low,
            timeoutSeconds: 30
        )
        let result = try await MockSandboxExecutor().execute(command)
        try require(result.commandId == command.id, "sandbox executor command id mismatch")
        try require(result.output.contains("Create a sandbox draft"), "sandbox executor output mismatch")
    }

    private static func validateEncryptedTransport() throws {
        let key = SymmetricTransportKey(rawValue: Data(repeating: 7, count: 32))
        let wrongKey = SymmetricTransportKey(rawValue: Data(repeating: 9, count: 32))
        let plaintext = Data("remote command payload".utf8)

        let envelope = try AESGCMTransportCipher().seal(plaintext, using: key)
        try require(envelope.ciphertext != plaintext, "ciphertext should not equal plaintext")

        let opened = try AESGCMTransportCipher().open(envelope, using: key)
        try require(opened == plaintext, "decrypted payload mismatch")

        do {
            _ = try AESGCMTransportCipher().open(envelope, using: wrongKey)
            throw ValidationError("wrong key should not decrypt payload")
        } catch TransportCipherError.authenticationFailed {
        }
    }

    private static func validateEncryptedRemoteTransportCodec() throws {
        let codec = EncryptedRemoteTransportCodec()
        let key = SymmetricTransportKey(rawValue: Data(repeating: 3, count: 32))
        let command = RemoteCommand(instruction: "Create a report", risk: .low)
        let message = RemoteTransportMessage(type: .command, command: command)

        let envelope = try codec.encode(message, key: key)
        let decoded = try codec.decode(envelope, key: key)

        try require(decoded.type == .command, "transport message type mismatch")
        try require(decoded.command == command, "transport command mismatch")
    }

    // MARK: - New: streaming buffer

    private static func validateStreamingResponseBuffer() async throws {
        let buffer = StreamingResponseBuffer()

        // Subscribe first, then produce. Without ordering you race the producer against the
        // observer's registration and the early snapshots are missed.
        let stream = await buffer.observe()
        let observerTask = Task { () -> [String] in
            var seen: [String] = []
            for await snapshot in stream {
                seen.append(snapshot.text)
            }
            return seen
        }

        // Yield once so the iterator latches onto the stream before we begin producing.
        try await Task.sleep(nanoseconds: 5_000_000)
        await buffer.append(token: "Hel")
        try await Task.sleep(nanoseconds: 5_000_000)
        await buffer.append(token: "lo")
        try await Task.sleep(nanoseconds: 5_000_000)
        await buffer.append(token: " world")
        try await Task.sleep(nanoseconds: 5_000_000)
        await buffer.complete()

        let history = await observerTask.value

        try require(history.last == "Hello world", "buffer final text mismatch — got \(history.last ?? "nil")")
        // We accept any progression that ends with the full text. The intermediate snapshots
        // exist when the consumer keeps up; on slow CI the broadcast may coalesce. Either is fine.
        try require(history.contains("Hello world"), "final aggregate snapshot missing")

        let snap = await buffer.snapshot()
        try require(snap.isCompleted, "buffer should be marked completed")
        try require(snap.failure == nil, "buffer should have no failure")

        // Failure path
        let failBuffer = StreamingResponseBuffer()
        await failBuffer.append(token: "partial")
        await failBuffer.fail("provider exploded")
        let failSnap = await failBuffer.snapshot()
        try require(failSnap.failure == "provider exploded", "failure message lost")
        try require(failSnap.isCompleted, "failed buffer should be marked completed")
    }

    // MARK: - New: privacy preferences repo

    private static func validatePrivacyPreferences() throws {
        let repo = InMemoryPrivacyPreferencesRepository()
        let defaultPrefs = repo.load()
        try require(defaultPrefs.allowThirdPartyAPIs, "default allowThirdPartyAPIs should be true")
        try require(!defaultPrefs.enableLocalNetworkDiscovery, "default enableLocalNetworkDiscovery should be false")
        try require(defaultPrefs.redactBeforeSending, "default redactBeforeSending should be true")
        try require(defaultPrefs.retainAuditLogsDays == 30, "default retention should be 30 days")

        let updated = PrivacyPreferences(
            allowThirdPartyAPIs: false,
            enableLocalNetworkDiscovery: true,
            redactBeforeSending: true,
            retainAuditLogsDays: 14
        )
        repo.save(updated)
        try require(repo.load() == updated, "saved preferences not persisted")

        // UserDefaults backing — exercise the encode/decode path with an isolated suite.
        guard let suite = UserDefaults(suiteName: "aiagenthub.tests.\(UUID().uuidString)") else {
            throw ValidationError("could not create UserDefaults suite")
        }
        let userDefaultsRepo = UserDefaultsPrivacyPreferencesRepository(defaults: suite, key: "test.prefs")
        try require(userDefaultsRepo.load() == .default, "missing key should yield defaults")
        userDefaultsRepo.save(updated)
        try require(userDefaultsRepo.load() == updated, "UserDefaults repo did not round-trip")
        suite.removePersistentDomain(forName: "aiagenthub.tests")
    }

    // MARK: - New: session pin / restore / model bind

    private static func validateSessionMutationOperations() throws {
        let clock = FixedClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        let repo = InMemoryChatRepository(clock: clock)
        let modelA = UUID()
        let modelB = UUID()

        let chat1 = repo.createSession(title: "Chat 1", modelConfigId: modelA)
        let chat2 = repo.createSession(title: "Chat 2", modelConfigId: nil)

        // Pin: pinned should sort first regardless of updatedAt
        repo.setSessionPinned(chat2.id, isPinned: true)
        let ordered = repo.sessions(includeDeleted: false)
        try require(ordered.first?.id == chat2.id, "pinned session should sort first")
        try require(ordered.first?.isPinned == true, "pin flag not set")

        // Unpin
        repo.setSessionPinned(chat2.id, isPinned: false)
        try require(repo.session(id: chat2.id)?.isPinned == false, "unpin failed")

        // Per-session model rebind
        repo.setSessionModel(chat1.id, modelConfigId: modelB)
        try require(repo.session(id: chat1.id)?.modelConfigId == modelB, "model rebind failed")
        repo.setSessionModel(chat1.id, modelConfigId: nil)
        try require(repo.session(id: chat1.id)?.modelConfigId == nil, "model unbind failed")

        // Soft delete + restore
        repo.softDeleteSession(chat2.id)
        try require(repo.sessions(includeDeleted: false).contains(where: { $0.id == chat2.id }) == false, "soft-deleted session should be hidden")
        repo.restoreSession(chat2.id)
        try require(repo.session(id: chat2.id)?.isDeleted == false, "restore did not flip isDeleted")
        try require(repo.session(id: chat2.id)?.deleteExpireAt == nil, "restore did not clear delete expiry")
    }

    // MARK: - New: streaming chat orchestrator path

    private static func validateStreamingChatOrchestrator() async throws {
        let repository = InMemoryChatRepository()
        let session = repository.createSession(title: "Streaming", modelConfigId: nil)
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
            aiService: StubAIService(events: [.token("Hel"), .token("lo"), .completed]),
            redactor: PrivacyRedactor(),
            contextBuilder: ContextBuilder(maxCharacters: 500)
        )
        let buffer = StreamingResponseBuffer()

        let response = try await orchestrator.sendUserMessage(
            "Hi",
            in: session.id,
            using: model,
            tools: [],
            streamingBuffer: buffer
        )

        try require(response == "Hello", "streaming chat aggregated text mismatch")
        let final = await buffer.snapshot()
        try require(final.text == "Hello", "buffer should reflect aggregated stream")
        try require(final.isCompleted, "buffer should be marked completed at end of stream")
    }

    // MARK: - Round 9: provider usage parsing

    private static func validateOpenAIUsageParsing() throws {
        let payload = """
        data: {"choices":[{"delta":{"content":"Hi"}}]}

        data: {"choices":[],"usage":{"prompt_tokens":7,"completion_tokens":3}}

        data: [DONE]

        """
        let events = try OpenAICompatibleSSEParser().parse(payload.data(using: .utf8)!)
        try require(events.contains(.token("Hi")), "OpenAI token missing in events")
        try require(events.contains(.usage(TokenUsage(promptTokens: 7, completionTokens: 3))), "OpenAI usage chunk not parsed")
        try require(events.contains(.completed), "OpenAI completion missing")
    }

    private static func validateClaudeUsageParsing() throws {
        let payload = """
        event: message_start
        data: {"type":"message_start","message":{"usage":{"input_tokens":12,"output_tokens":0}}}

        event: content_block_delta
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}

        event: message_delta
        data: {"type":"message_delta","usage":{"output_tokens":5}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        let events = try ClaudeSSEParser().parse(payload.data(using: .utf8)!)
        try require(events.contains(.token("Hi")), "Claude token missing")
        // Final assembled usage should be 12 input / 5 output
        try require(
            events.contains(.usage(TokenUsage(promptTokens: 12, completionTokens: 5))),
            "Claude assembled usage missing — got events: \(events)"
        )
        // And usage must come before completed
        if let usageIdx = events.firstIndex(of: .usage(TokenUsage(promptTokens: 12, completionTokens: 5))),
           let completedIdx = events.firstIndex(of: .completed) {
            try require(usageIdx < completedIdx, "Claude usage should arrive before .completed")
        }
    }

    // MARK: - Round 10: audit retention follows preference

    private static func validateAuditRetentionFollowsPreference() async throws {
        let auditStore = InMemoryAuditLogStore()
        let retentionRef = RetentionRef(days: 30)
        let registry = ToolRegistry(
            tools: [ValidationEchoTool()],
            auditStore: auditStore,
            authorization: StaticToolAuthorization(decision: .approved),
            retentionDaysProvider: { retentionRef.days },
            clock: FixedClock(now: Date(timeIntervalSince1970: 1_700_000_000))
        )

        _ = try await registry.execute(
            toolName: "echo",
            arguments: ["text": .string("first")],
            sessionId: UUID()
        )
        let first = auditStore.entries.last!
        let delta = first.expiresAt.timeIntervalSince(first.createdAt)
        try require(abs(delta - 30 * 86_400) < 1, "default retention should be 30 days, got \(delta / 86_400) days")

        // Shrink retention — next entry should respect it
        retentionRef.days = 7
        _ = try await registry.execute(
            toolName: "echo",
            arguments: ["text": .string("second")],
            sessionId: UUID()
        )
        let second = auditStore.entries.last!
        let delta2 = second.expiresAt.timeIntervalSince(second.createdAt)
        try require(abs(delta2 - 7 * 86_400) < 1, "updated retention should be 7 days, got \(delta2 / 86_400) days")

        // Older entry's expiresAt should be unchanged
        try require(auditStore.entries.first!.expiresAt == first.expiresAt, "existing entries should keep their original expiresAt")
    }

    // MARK: - Round 11: JSON export

    private static func validateJSONExport() throws {
        let exporter = ConversationExporter()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let messages: [ChatMessageDTO] = [
            ChatMessageDTO(role: .user, content: "Hi", timestamp: baseDate),
            ChatMessageDTO(role: .assistant, content: "Hello", timestamp: baseDate.addingTimeInterval(2))
        ]
        let json = exporter.export(
            sessionTitle: "Trip",
            messages: messages,
            tokenUsage: TokenUsage(promptTokens: 10, completionTokens: 5),
            format: .json
        )

        guard let data = json.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ValidationError("JSON export did not produce valid JSON")
        }
        try require(obj["title"] as? String == "Trip", "JSON export missing title")
        let msgs = obj["messages"] as? [[String: Any]]
        try require(msgs?.count == 2, "JSON export should have 2 messages")
        try require(msgs?.first?["role"] as? String == "user", "first message should be user")
        let usage = obj["tokenUsage"] as? [String: Any]
        try require(usage?["promptTokens"] as? Int == 10, "JSON usage promptTokens missing")
        try require(usage?["completionTokens"] as? Int == 5, "JSON usage completionTokens missing")

        // Format extension and display
        try require(ConversationExportFormat.json.fileExtension == "json", "JSON file extension wrong")
        try require(ConversationExportFormat.markdown.fileExtension == "md", "Markdown file extension wrong")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw ValidationError(message)
        }
    }

    // MARK: - Round 24: relative time formatter

    private static func validateRelativeTimeFormatter() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000) // arbitrary fixed instant
        let clock = FixedClock(now: now)
        let formatter = RelativeTimeFormatter(clock: clock)

        try require(formatter.string(from: now) == "just now", "now → just now")
        try require(formatter.string(from: now.addingTimeInterval(-30)) == "just now", "<60s → just now")

        let fiveMin = formatter.string(from: now.addingTimeInterval(-5 * 60))
        try require(fiveMin == "5m ago", "5m ago — got '\(fiveMin)'")

        let twoHours = formatter.string(from: now.addingTimeInterval(-2 * 3600))
        try require(twoHours == "2h ago", "2h ago — got '\(twoHours)'")

        // Yesterday: same calendar boundary as `now` minus one day
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        try require(formatter.string(from: yesterday) == "yesterday", "yesterday — got '\(formatter.string(from: yesterday))'")
    }

    // MARK: - Round 25: session date grouper

    private static func validateSessionDateGrouper() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let clock = FixedClock(now: now)
        let grouper = SessionDateGrouper(clock: clock)

        let calendar = Calendar.current
        let today = ChatSessionRecord(title: "today", createdAt: now, updatedAt: now)
        let pinned = ChatSessionRecord(
            title: "pinned",
            createdAt: now.addingTimeInterval(-30 * 86_400),
            updatedAt: now.addingTimeInterval(-30 * 86_400),
            isPinned: true
        )
        let yesterday = ChatSessionRecord(
            title: "yest",
            createdAt: calendar.date(byAdding: .day, value: -1, to: now)!,
            updatedAt: calendar.date(byAdding: .day, value: -1, to: now)!
        )
        let threeDaysAgo = ChatSessionRecord(
            title: "3d",
            createdAt: calendar.date(byAdding: .day, value: -3, to: now)!,
            updatedAt: calendar.date(byAdding: .day, value: -3, to: now)!
        )
        let twoWeeksAgo = ChatSessionRecord(
            title: "2w",
            createdAt: calendar.date(byAdding: .day, value: -14, to: now)!,
            updatedAt: calendar.date(byAdding: .day, value: -14, to: now)!
        )
        let twoMonthsAgo = ChatSessionRecord(
            title: "older",
            createdAt: calendar.date(byAdding: .day, value: -60, to: now)!,
            updatedAt: calendar.date(byAdding: .day, value: -60, to: now)!
        )

        let groups = grouper.group([pinned, today, yesterday, threeDaysAgo, twoWeeksAgo, twoMonthsAgo])

        // Pinned must come first
        try require(groups.first?.bucket == .pinned, "pinned should be first group")
        try require(groups.first?.sessions.count == 1, "pinned should have 1 session")

        let bucketsByTitle = Dictionary(uniqueKeysWithValues: groups.map { ($0.bucket, $0.sessions.map(\.title)) })
        try require(bucketsByTitle[.today] == ["today"], "today bucket wrong")
        try require(bucketsByTitle[.yesterday] == ["yest"], "yesterday wrong")
        try require(bucketsByTitle[.thisWeek] == ["3d"], "this week wrong")
        try require(bucketsByTitle[.thisMonth] == ["2w"], "this month wrong")
        try require(bucketsByTitle[.earlier] == ["older"], "earlier wrong")

        // Empty input
        try require(grouper.group([]).isEmpty, "empty input → empty groups")
    }

    // MARK: - Round 27: error message mapper

    private static func validateErrorMessageMapper() throws {
        // Each enum case maps to a non-empty, classified message
        let cases: [any Error] = [
            ModelConfigurationError.missingAPIKey(UUID()),
            ModelConfigurationError.noEnabledModel,
            ChatOrchestratorError.thirdPartyDisabled(provider: .openai),
            ChatOrchestratorError.noUserMessageToReplay,
            ToolExecutionError.toolNotFound("x"),
            ToolExecutionError.authorizationCancelled,
            AIHTTPClientError.missingEndpoint,
            AIHTTPClientError.missingAPIKey,
            AIHTTPClientError.invalidResponse,
            AIHTTPClientError.httpStatus(401),
            AIHTTPClientError.httpStatus(429),
            AIHTTPClientError.httpStatus(500),
            AIHTTPClientError.httpStatus(404),
            CancellationError(),
        ]

        for error in cases {
            let mapped = ErrorMessageMapper.message(for: error)
            try require(!mapped.title.isEmpty, "title empty for \(error)")
            try require(!mapped.detail.isEmpty, "detail empty for \(error)")
            // The detail should never just say the raw error description for known cases
            let raw = String(describing: error)
            try require(mapped.detail != raw, "detail still raw for \(error)")
        }

        // HTTP status branching
        let unauthorized = ErrorMessageMapper.message(for: AIHTTPClientError.httpStatus(401))
        try require(unauthorized.title.contains("Authentication"), "401 should mention auth")
        let rate = ErrorMessageMapper.message(for: AIHTTPClientError.httpStatus(429))
        try require(rate.title.contains("Rate"), "429 should mention rate")
        let server = ErrorMessageMapper.message(for: AIHTTPClientError.httpStatus(503))
        try require(server.title.contains("Provider"), "5xx should mention provider")

        // Third-party message names the provider so users know which one to enable
        let blocked = ErrorMessageMapper.message(for: ChatOrchestratorError.thirdPartyDisabled(provider: .openai))
        try require(blocked.title.contains("OpenAI"), "third-party error should name the provider")

        // NSURLError fallback
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let timeoutMapped = ErrorMessageMapper.message(for: timeout)
        try require(timeoutMapped.title.contains("timed out"), "timeout should map nicely")

        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let offlineMapped = ErrorMessageMapper.message(for: offline)
        try require(offlineMapped.title.contains("internet"), "offline should map nicely")
    }

    // MARK: - Round 19: markdown segment parser

    private static func validateMessageSegmentParser() throws {
        // Plain text → one inline segment
        let plain = MessageSegmentParser.parse("just plain text")
        try require(plain == [.inline("just plain text")], "plain text segment mismatch")

        // Inline + code + inline
        let mixed = MessageSegmentParser.parse("""
        Here is some Swift:

        ```swift
        let x = 1
        print(x)
        ```

        And after.
        """)
        try require(mixed.count == 3, "mixed expected 3 segments, got \(mixed.count)")
        if case let .code(lang, body) = mixed[1] {
            try require(lang == "swift", "language should be swift")
            try require(body.contains("let x = 1"), "body should contain code")
        } else {
            throw ValidationError("second segment should be code, got \(mixed[1])")
        }

        // Unclosed fence — trailing becomes code
        let unclosed = MessageSegmentParser.parse("intro\n```\ncode without closing")
        try require(unclosed.count == 2, "unclosed fence should still yield 2 segments")
        if case let .code(lang, body) = unclosed[1] {
            try require(lang == nil, "no language")
            try require(body == "code without closing", "body preserved")
        } else {
            throw ValidationError("trailing should be code")
        }

        // No fences, multi-line inline
        let multiline = MessageSegmentParser.parse("Line one\nLine two")
        try require(multiline.count == 1, "no fence should yield single inline")
    }

    // MARK: - Round 20: turn-aware context truncation

    private static func validateContextBuilderTurnAware() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // Build 5 turns. Earlier turns should be dropped first when budget shrinks.
        var messages: [ChatMessageDTO] = []
        for i in 0..<5 {
            messages.append(ChatMessageDTO(
                id: UUID(),
                role: .user,
                content: "Q\(i): \(String(repeating: "x", count: 100))",
                timestamp: base.addingTimeInterval(TimeInterval(i * 10))
            ))
            messages.append(ChatMessageDTO(
                id: UUID(),
                role: .assistant,
                content: "A\(i): \(String(repeating: "y", count: 100))",
                timestamp: base.addingTimeInterval(TimeInterval(i * 10 + 1))
            ))
        }

        // Tiny budget: must still keep the newest turn whole.
        let tiny = ContextBuilder(maxCharacters: 50).build(from: messages)
        try require(tiny.count == 2, "tiny budget should yield newest turn = 2 messages, got \(tiny.count)")
        try require(tiny.first?.content.hasPrefix("Q4") == true, "kept turn must be newest user")
        try require(tiny.last?.content.hasPrefix("A4") == true, "kept turn must include assistant")

        // Medium budget: should keep ~last 2 turns whole
        let medium = ContextBuilder(maxCharacters: 600).build(from: messages)
        try require(medium.count == 4 || medium.count == 6, "medium budget should keep 2 or 3 turns whole, got \(medium.count)")
        try require(medium.last?.content.hasPrefix("A4") == true, "last message should be newest assistant")

        // Generous budget: everything kept
        let generous = ContextBuilder(maxCharacters: 10_000).build(from: messages)
        try require(generous.count == 10, "generous budget should keep everything")

        // System message preserved regardless
        let withSystem = [
            ChatMessageDTO(role: .system, content: "Always be concise."),
        ] + messages
        let result = ContextBuilder(maxCharacters: 50).build(from: withSystem)
        try require(result.contains { $0.role == .system }, "system message must survive")
        try require(result.first?.role == .system, "system message must come first")
    }

    // MARK: - Round 21: bookmark toggle

    private static func validateBookmarkToggle() throws {
        let repository = InMemoryChatRepository()
        let session = repository.createSession(title: "Bookmarks", modelConfigId: nil)
        let m1 = ChatMessageDTO(id: UUID(), role: .user, content: "first", timestamp: Date(timeIntervalSince1970: 1))
        let m2 = ChatMessageDTO(id: UUID(), role: .assistant, content: "second", timestamp: Date(timeIntervalSince1970: 2))
        repository.appendMessage(m1, to: session.id)
        repository.appendMessage(m2, to: session.id)

        // Default not bookmarked
        try require(repository.messages(for: session.id).contains { $0.id == m1.id && !$0.isBookmarked }, "default isBookmarked should be false")

        // Toggle on
        repository.toggleBookmark(m1.id, in: session.id)
        try require(repository.messages(for: session.id).first { $0.id == m1.id }?.isBookmarked == true, "toggle on failed")

        // Toggle off
        repository.toggleBookmark(m1.id, in: session.id)
        try require(repository.messages(for: session.id).first { $0.id == m1.id }?.isBookmarked == false, "toggle off failed")

        // Unknown id is a no-op
        repository.toggleBookmark(UUID(), in: session.id)
        // No crash → pass
    }

    // MARK: - Round 22: slash command parser

    private static func validateSlashCommandParser() throws {
        // Known command + args
        if case let .command(cmd, args) = SlashCommandParser.parse("/system You are concise.") {
            try require(cmd == .system, "should be .system")
            try require(args == "You are concise.", "args mismatch — got \(args)")
        } else {
            throw ValidationError("expected .system command")
        }

        // Known command no args
        if case let .command(cmd, args) = SlashCommandParser.parse("/help") {
            try require(cmd == .help, "should be .help")
            try require(args.isEmpty, "no args expected")
        } else {
            throw ValidationError("expected .help command")
        }

        // Whitespace tolerance
        if case .command = SlashCommandParser.parse("   /clear   ") {
        } else {
            throw ValidationError("whitespace should be tolerated")
        }

        // Not a command — no slash
        try require(SlashCommandParser.parse("hello") == .notACommand, "plain text should not parse")
        // Unknown command name
        try require(SlashCommandParser.parse("/notarealcommand") == .notACommand, "unknown name should not parse")

        // Suggestions
        let all = SlashCommandParser.suggestions(forPrefix: "/")
        try require(all == SlashCommand.allCases, "empty filter should suggest all")
        let sy = SlashCommandParser.suggestions(forPrefix: "/sy")
        try require(sy == [.system], "/sy should suggest .system only")
        let empty = SlashCommandParser.suggestions(forPrefix: "hello")
        try require(empty.isEmpty, "no leading slash → no suggestions")
        // Once user typed past the space, suggestions stop
        let withSpace = SlashCommandParser.suggestions(forPrefix: "/system foo")
        try require(withSpace.isEmpty, "after the space, no suggestions")
    }

    // MARK: - Round 23: token estimator

    private static func validateTokenEstimator() throws {
        try require(TokenEstimator.estimateTokens(in: "") == 0, "empty string should be 0")
        // ASCII heuristic: chars / 4 floor 1
        let ascii = TokenEstimator.estimateTokens(in: String(repeating: "x", count: 40))
        try require(ascii == 10, "40 ascii chars → 10 tokens, got \(ascii)")

        // CJK: each char ≈ 1 token
        let chinese = "你好世界你好世界"
        let cjk = TokenEstimator.estimateTokens(in: chinese)
        try require(cjk >= 8, "CJK should yield ≥ char count, got \(cjk) for 8 chars")

        // Mixed should respect the higher of the two
        let mixed = "Hello 你好"
        let m = TokenEstimator.estimateTokens(in: mixed)
        try require(m >= 2, "mixed should count CJK chars")
    }

    // MARK: - Round 13: system prompt injection

    private static func validateSystemPromptInjection() async throws {
        let repository = InMemoryChatRepository()
        let session = repository.createSession(title: "System prompt", modelConfigId: nil)
        repository.setSessionSystemPrompt(session.id, systemPrompt: "Speak in haikus only.")
        try require(repository.session(id: session.id)?.systemPrompt == "Speak in haikus only.", "system prompt did not persist")

        // Whitespace-only is normalized to nil
        repository.setSessionSystemPrompt(session.id, systemPrompt: "   \n  ")
        try require(repository.session(id: session.id)?.systemPrompt == nil, "whitespace prompt should normalize to nil")

        // Re-set and confirm orchestrator prepends it
        repository.setSessionSystemPrompt(session.id, systemPrompt: "Be terse.")

        final class CapturingService: AIService, @unchecked Sendable {
            var captured: [ChatMessageDTO] = []
            let lock = NSLock()
            func streamChat(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
                lock.withLock { captured = request.messages }
                return AsyncThrowingStream { continuation in
                    continuation.yield(.token("ok"))
                    continuation.finish()
                }
            }
        }
        let capturer = CapturingService()
        let orchestrator = ChatOrchestrator(repository: repository, aiService: capturer)
        let model = ResolvedModelConfig(
            id: UUID(), provider: .openai, name: "Test", modelName: "gpt-test",
            endpoint: URL(string: "https://example.com"), apiKey: "sk-test",
            temperature: 0.7, maxTokens: 100
        )
        _ = try await orchestrator.sendUserMessage("hi", in: session.id, using: model)

        let captured = capturer.lock.withLock { capturer.captured }
        try require(captured.first?.role == .system, "system prompt must be first message — got role \(captured.first?.role.rawValue ?? "nil")")
        try require(captured.first?.content == "Be terse.", "system prompt content mismatch")

        // System prompt presets are well-formed
        for preset in SystemPromptPreset.allCases {
            try require(!preset.title.isEmpty, "preset \(preset) missing title")
            try require(!preset.prompt.isEmpty, "preset \(preset) missing prompt")
            try require(!preset.summary.isEmpty, "preset \(preset) missing summary")
        }
    }

    // MARK: - Round 14: message edit and trailing deletion

    private static func validateMessageEditAndDeletion() throws {
        let repository = InMemoryChatRepository()
        let session = repository.createSession(title: "Edit", modelConfigId: nil)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let user1 = ChatMessageDTO(id: UUID(), role: .user, content: "First", timestamp: base)
        let assistant1 = ChatMessageDTO(id: UUID(), role: .assistant, content: "Reply 1", timestamp: base.addingTimeInterval(1))
        let user2 = ChatMessageDTO(id: UUID(), role: .user, content: "Second", timestamp: base.addingTimeInterval(2))
        let assistant2 = ChatMessageDTO(id: UUID(), role: .assistant, content: "Reply 2", timestamp: base.addingTimeInterval(3))

        repository.appendMessage(user1, to: session.id)
        repository.appendMessage(assistant1, to: session.id)
        repository.appendMessage(user2, to: session.id)
        repository.appendMessage(assistant2, to: session.id)

        // Update content
        repository.updateMessageContent(user1.id, in: session.id, newContent: "First (edited)")
        let updatedFirst = repository.messages(for: session.id).first(where: { $0.id == user1.id })
        try require(updatedFirst?.content == "First (edited)", "edit did not persist")

        // Delete messages after user1 — should drop assistant1, user2, assistant2
        repository.deleteMessagesAfter(user1.id, in: session.id)
        let remaining = repository.messages(for: session.id)
        try require(remaining.count == 1, "deleteMessagesAfter should leave just the anchor — got \(remaining.count)")
        try require(remaining.first?.id == user1.id, "remaining message id mismatch")

        // No-op when cutoff is the last message
        repository.deleteMessagesAfter(user1.id, in: session.id)
        try require(repository.messages(for: session.id).count == 1, "no-op delete should not change count")

        // No-op when message id is not found
        repository.deleteMessagesAfter(UUID(), in: session.id)
        try require(repository.messages(for: session.id).count == 1, "missing cutoff should be a no-op")
    }

    // MARK: - Round 17: branch session

    private static func validateBranchSession() throws {
        let repository = InMemoryChatRepository()
        let original = repository.createSession(title: "Source", modelConfigId: UUID())
        repository.setSessionSystemPrompt(original.id, systemPrompt: "Be helpful.")
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let m1 = ChatMessageDTO(id: UUID(), role: .user, content: "A", timestamp: base)
        let m2 = ChatMessageDTO(id: UUID(), role: .assistant, content: "B", timestamp: base.addingTimeInterval(1))
        let m3 = ChatMessageDTO(id: UUID(), role: .user, content: "C", timestamp: base.addingTimeInterval(2))
        repository.appendMessage(m1, to: original.id)
        repository.appendMessage(m2, to: original.id)
        repository.appendMessage(m3, to: original.id)

        // Branch up to m2
        guard let branched = repository.branchSession(original.id, upToMessageId: m2.id, newTitle: "Branched") else {
            throw ValidationError("branchSession returned nil")
        }
        try require(branched.id != original.id, "branch should produce a new id")
        try require(branched.title == "Branched", "branch title mismatch")
        try require(branched.modelConfigId == original.modelConfigId, "branch should inherit modelConfigId")
        try require(branched.systemPrompt == "Be helpful.", "branch should inherit system prompt")

        let branchedMessages = repository.messages(for: branched.id)
        try require(branchedMessages.count == 2, "branch should contain 2 messages — got \(branchedMessages.count)")
        try require(branchedMessages.map(\.content) == ["A", "B"], "branch content mismatch")
        // Branched messages must have fresh ids — editing one shouldn't affect the source
        try require(branchedMessages[0].id != m1.id, "branched message id must be different")

        // Source untouched
        try require(repository.messages(for: original.id).count == 3, "source session should not be modified")

        // Unknown cutoff returns nil
        try require(repository.branchSession(original.id, upToMessageId: UUID(), newTitle: "X") == nil, "branch with bad cutoff should return nil")
    }

    // MARK: - Round 15: stop reason parsing

    private static func validateStopReasonParsing() throws {
        // OpenAI mapping
        try require(StopReason.fromOpenAI("stop") == .endTurn, "OpenAI stop → endTurn")
        try require(StopReason.fromOpenAI("length") == .maxTokens, "OpenAI length → maxTokens")
        try require(StopReason.fromOpenAI("tool_calls") == .toolUse, "OpenAI tool_calls → toolUse")
        try require(StopReason.fromOpenAI("content_filter") == .contentFilter, "OpenAI content_filter")
        try require(StopReason.fromOpenAI(nil) == nil, "nil → nil")

        // Claude mapping
        try require(StopReason.fromClaude("end_turn") == .endTurn, "Claude end_turn")
        try require(StopReason.fromClaude("max_tokens") == .maxTokens, "Claude max_tokens")
        try require(StopReason.fromClaude("tool_use") == .toolUse, "Claude tool_use")
        try require(StopReason.fromClaude("stop_sequence") == .stopSequence, "Claude stop_sequence")

        // Truncation predicate
        try require(StopReason.maxTokens.isTruncation, "maxTokens should be truncation")
        try require(!StopReason.endTurn.isTruncation, "endTurn should not be truncation")

        // Display label populated
        for reason in [StopReason.endTurn, .maxTokens, .toolUse, .stopSequence, .contentFilter, .other] {
            try require(!reason.displayLabel.isEmpty, "stop reason \(reason) missing display label")
        }

        // OpenAI SSE parse — finish_reason carried through
        let payload = """
        data: {"choices":[{"delta":{"content":"Hi"},"finish_reason":"length"}]}

        data: [DONE]

        """
        let events = try OpenAICompatibleSSEParser().parse(payload.data(using: .utf8)!)
        try require(events.contains(.stop(.maxTokens)), "OpenAI finish_reason should surface as .stop(.maxTokens)")

        // Claude SSE parse — message_delta stop_reason
        let claudePayload = """
        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        let claudeEvents = try ClaudeSSEParser().parse(claudePayload.data(using: .utf8)!)
        try require(claudeEvents.contains(.stop(.endTurn)), "Claude stop_reason should surface")
    }

    // MARK: - Round 16: last session store

    private static func validateLastSessionStore() throws {
        let memoryStore = InMemoryLastSessionStore()
        try require(memoryStore.load() == nil, "fresh store should return nil")
        let id = UUID()
        memoryStore.save(id)
        try require(memoryStore.load() == id, "saved id should round-trip")
        memoryStore.save(nil)
        try require(memoryStore.load() == nil, "saving nil should clear")

        // UserDefaults backing
        guard let suite = UserDefaults(suiteName: "aiagenthub.tests.lastsession.\(UUID().uuidString)") else {
            throw ValidationError("could not create suite")
        }
        let defaults = UserDefaultsLastSessionStore(defaults: suite, key: "last")
        try require(defaults.load() == nil, "fresh UserDefaults store should return nil")
        defaults.save(id)
        try require(defaults.load() == id, "UserDefaults round-trip")
        defaults.save(nil)
        try require(defaults.load() == nil, "UserDefaults clear")
    }

    // MARK: - Round 4: privacy enforcement

    private static func validateThirdPartyPrivacyGate() async throws {
        let repository = InMemoryChatRepository()
        let session = repository.createSession(title: "Privacy gate", modelConfigId: nil)
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
        let prefs = PrivacyPreferences(
            allowThirdPartyAPIs: false,
            enableLocalNetworkDiscovery: false,
            redactBeforeSending: true,
            retainAuditLogsDays: 30
        )
        let orchestrator = ChatOrchestrator(
            repository: repository,
            aiService: StubAIService(events: [.token("should-not-reach"), .completed]),
            privacyPreferences: prefs
        )

        do {
            _ = try await orchestrator.sendUserMessage("Hello", in: session.id, using: model)
            throw ValidationError("third-party gate should have thrown")
        } catch ChatOrchestratorError.thirdPartyDisabled(let provider) {
            try require(provider == .openai, "third-party error should carry provider")
        }

        // No messages should have been persisted
        try require(repository.messages(for: session.id).isEmpty, "no messages should be appended when blocked")

        // Apple on-device should bypass the gate
        let appleModel = ResolvedModelConfig(
            id: UUID(),
            provider: .apple,
            name: "Apple",
            modelName: "on-device",
            endpoint: nil,
            apiKey: nil,
            temperature: 0.7,
            maxTokens: 100
        )
        let appleOrchestrator = ChatOrchestrator(
            repository: repository,
            aiService: StubAIService(events: [.token("local-ok"), .completed]),
            privacyPreferences: prefs
        )
        let response = try await appleOrchestrator.sendUserMessage("Hi", in: session.id, using: appleModel)
        try require(response == "local-ok", "Apple provider should bypass third-party gate")
    }

    private static func validateRedactionOptOut() async throws {
        let repository = InMemoryChatRepository()
        let session = repository.createSession(title: "Redaction opt-out", modelConfigId: nil)
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

        // Default prefs: redact
        let redactOrch = ChatOrchestrator(
            repository: repository,
            aiService: StubAIService(events: [.completed]),
            redactor: PrivacyRedactor(deviceNames: []),
            privacyPreferences: .default
        )
        _ = try await redactOrch.sendUserMessage(
            "Email me at user@example.com",
            in: session.id,
            using: model
        )
        let redactedFirst = repository.messages(for: session.id).first { $0.role == .user }?.content
        try require(redactedFirst?.contains("[email]") == true, "default prefs should redact email")
        try require(redactedFirst?.contains("user@example.com") == false, "raw email leaked despite redaction")

        // Opted-out prefs: do not redact
        let optedOut = PrivacyPreferences(
            allowThirdPartyAPIs: true,
            enableLocalNetworkDiscovery: false,
            redactBeforeSending: false,
            retainAuditLogsDays: 30
        )
        let rawOrch = ChatOrchestrator(
            repository: repository,
            aiService: StubAIService(events: [.completed]),
            redactor: PrivacyRedactor(deviceNames: []),
            privacyPreferences: optedOut
        )
        _ = try await rawOrch.sendUserMessage(
            "Send to other@example.com",
            in: session.id,
            using: model
        )
        let rawMessages = repository.messages(for: session.id).filter { $0.role == .user }
        // Find the most recent
        let mostRecent = rawMessages.last?.content
        try require(mostRecent?.contains("other@example.com") == true, "opted-out user should keep raw email in stored message")
    }

    // MARK: - Round 5: auto-titling

    private static func validateSessionTitleDeriver() throws {
        let deriver = SessionTitleDeriver(maxCharacters: 30, fallback: "New Chat")

        try require(deriver.derive(from: "  ") == "New Chat", "whitespace should fall back")
        try require(deriver.derive(from: "Hello") == "Hello", "short message should pass through")
        try require(
            deriver.derive(from: "Hello!") == "Hello",
            "trailing punctuation should be trimmed"
        )

        let long = "Could you summarize this lengthy article for me please thanks a lot"
        let derived = deriver.derive(from: long)
        try require(derived.count <= 31, "title should be bounded — got \(derived.count) chars")
        try require(derived.hasSuffix("…"), "long title should end with ellipsis")
        try require(!derived.contains("  "), "title should collapse internal whitespace")
    }

    private static func validateAutoTitling() async throws {
        let repository = InMemoryChatRepository()
        let session = repository.createSession(title: "New Chat", modelConfigId: nil)
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
            aiService: StubAIService(events: [.token("ok"), .completed]),
            redactor: PrivacyRedactor(deviceNames: [])
        )

        _ = try await orchestrator.sendUserMessage(
            "What's the capital of France?",
            in: session.id,
            using: model
        )

        let after = repository.session(id: session.id)
        try require(after?.title == "What's the capital of France", "auto-title should be derived from first user message")

        // Second send shouldn't rename
        _ = try await orchestrator.sendUserMessage(
            "And the population?",
            in: session.id,
            using: model
        )
        try require(repository.session(id: session.id)?.title == "What's the capital of France", "subsequent sends must not rename")

        // Session with deliberate user title shouldn't get auto-renamed
        let custom = repository.createSession(title: "Travel planning", modelConfigId: nil)
        _ = try await orchestrator.sendUserMessage("Hello", in: custom.id, using: model)
        try require(repository.session(id: custom.id)?.title == "Travel planning", "user-set title should be preserved")
    }

    // MARK: - Round 7: regenerate

    private static func validateRegenerate() async throws {
        let repository = InMemoryChatRepository()
        let session = repository.createSession(title: "Regenerate", modelConfigId: nil)
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
        let firstOrch = ChatOrchestrator(
            repository: repository,
            aiService: StubAIService(events: [.token("first answer"), .completed])
        )
        _ = try await firstOrch.sendUserMessage("Tell me a joke", in: session.id, using: model)
        try require(repository.messages(for: session.id).count == 2, "expected user + assistant after first send")

        // Now regenerate with a different response
        let secondOrch = ChatOrchestrator(
            repository: repository,
            aiService: StubAIService(events: [.token("second answer"), .completed])
        )
        let regenerated = try await secondOrch.regenerateLastAssistantMessage(in: session.id, using: model)
        try require(regenerated == "second answer", "regenerate should produce new content")

        let after = repository.messages(for: session.id)
        try require(after.count == 2, "regenerate should keep one user + one assistant — got \(after.count)")
        try require(after.last?.role == .assistant, "trailing message should be assistant")
        try require(after.last?.content == "second answer", "trailing assistant should be the regenerated text")

        // Regenerate with empty history should throw
        let blank = repository.createSession(title: "Blank", modelConfigId: nil)
        do {
            _ = try await secondOrch.regenerateLastAssistantMessage(in: blank.id, using: model)
            throw ValidationError("regenerate on empty session should throw")
        } catch ChatOrchestratorError.noUserMessageToReplay {
        }
    }

    // MARK: - Round 8: search + export

    private static func validateMessageSearch() async throws {
        let repository = InMemoryChatRepository()
        let s1 = repository.createSession(title: "Trip planning", modelConfigId: nil)
        let s2 = repository.createSession(title: "Recipes", modelConfigId: nil)
        repository.appendMessage(ChatMessageDTO(role: .user, content: "Best ramen in Tokyo?"), to: s1.id)
        repository.appendMessage(ChatMessageDTO(role: .assistant, content: "Tsuta and Afuri are great"), to: s1.id)
        repository.appendMessage(ChatMessageDTO(role: .user, content: "Carbonara recipe please"), to: s2.id)

        let hits = repository.search(query: "ramen", limit: 10)
        try require(hits.count == 1, "expected one match for 'ramen' — got \(hits.count)")
        try require(hits.first?.sessionId == s1.id, "ramen hit should be in trip session")

        let caseInsensitive = repository.search(query: "RAMEN", limit: 10)
        try require(caseInsensitive.count == 1, "search should be case-insensitive")

        try require(repository.search(query: "  ", limit: 10).isEmpty, "empty query should return no hits")

        // Soft-deleted session content should be excluded
        repository.softDeleteSession(s1.id)
        try require(repository.search(query: "ramen", limit: 10).isEmpty, "deleted sessions should be excluded from search")
    }

    private static func validateConversationExporter() throws {
        let exporter = ConversationExporter()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let messages: [ChatMessageDTO] = [
            ChatMessageDTO(role: .user, content: "Hi", timestamp: baseDate),
            ChatMessageDTO(role: .assistant, content: "Hello there", timestamp: baseDate.addingTimeInterval(2)),
            ChatMessageDTO(role: .tool, content: "{\"summary\":\"done\"}", timestamp: baseDate.addingTimeInterval(3))
        ]
        let usage = TokenUsage(promptTokens: 12, completionTokens: 34)
        let md = exporter.export(sessionTitle: "Demo", messages: messages, tokenUsage: usage)

        try require(md.contains("# Demo"), "export should have title heading")
        try require(md.contains("## You"), "user header missing")
        try require(md.contains("## Assistant"), "assistant header missing")
        try require(md.contains("## Tool call"), "tool header missing")
        try require(md.contains("```text"), "tool result should be fenced")
        try require(md.contains("Hello there"), "assistant content should appear")
        try require(md.contains("12 prompt"), "token usage should be included when provided")

        // No usage path
        let noUsage = exporter.export(sessionTitle: "Demo", messages: messages, tokenUsage: nil)
        try require(!noUsage.contains("Token usage"), "no usage footer when not provided")
    }

    // MARK: - Round 6: token usage + cancellation

    private static func validateTokenUsageTracking() async throws {
        let repository = InMemoryChatRepository()
        let session = repository.createSession(title: "Usage", modelConfigId: nil)
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
            aiService: StubAIService(events: [
                .token("Hi"),
                .usage(TokenUsage(promptTokens: 10, completionTokens: 5)),
                .completed
            ])
        )
        _ = try await orchestrator.sendUserMessage("Hello", in: session.id, using: model)

        let after1 = repository.tokenUsage(for: session.id)
        try require(after1.promptTokens == 10, "prompt tokens not recorded — got \(after1.promptTokens)")
        try require(after1.completionTokens == 5, "completion tokens not recorded — got \(after1.completionTokens)")

        // Second call should accumulate
        let orchestrator2 = ChatOrchestrator(
            repository: repository,
            aiService: StubAIService(events: [
                .usage(TokenUsage(promptTokens: 3, completionTokens: 2)),
                .completed
            ])
        )
        _ = try await orchestrator2.sendUserMessage("Again", in: session.id, using: model)
        let after2 = repository.tokenUsage(for: session.id)
        try require(after2.promptTokens == 13, "prompt tokens should accumulate — got \(after2.promptTokens)")
        try require(after2.completionTokens == 7, "completion tokens should accumulate — got \(after2.completionTokens)")
    }

    private static func validateGenerationCancellation() async throws {
        // Build an AI service that yields a token then awaits — the loop should detect the
        // cancellation when checkCancellation() fires between events.
        struct SlowService: AIService {
            func streamChat(request: ChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
                AsyncThrowingStream { continuation in
                    Task {
                        continuation.yield(.token("partial"))
                        // Sleep long enough for the outer task to cancel us
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        continuation.yield(.token("never"))
                        continuation.finish()
                    }
                }
            }
        }

        let repository = InMemoryChatRepository()
        let session = repository.createSession(title: "Cancel", modelConfigId: nil)
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
            aiService: SlowService()
        )

        let tracker = ActiveGenerationTracker()
        let task = Task {
            do {
                _ = try await orchestrator.sendUserMessage("Slow message", in: session.id, using: model)
            } catch {
                // expected
            }
        }
        await tracker.register(task)
        // Let it produce the first token
        try await Task.sleep(nanoseconds: 50_000_000)
        await tracker.cancel()
        _ = await task.value

        let stored = repository.messages(for: session.id)
        try require(stored.contains { $0.role == .user }, "user message should still be persisted on cancel")
        let assistantPartial = stored.first { $0.role == .assistant }?.content
        try require(assistantPartial == "partial", "cancelled assistant message should keep partial content — got \(assistantPartial ?? "nil")")
        let stillActive = await tracker.hasActiveTask
        try require(!stillActive, "tracker should clear after cancel")
    }

    private static func awaitEvents(
        from stream: AsyncThrowingStream<ChatStreamEvent, Error>
    ) async throws -> [ChatStreamEvent] {
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private static func requireJSONObject(_ data: Data?) throws -> [String: Any] {
        guard let data,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ValidationError("expected JSON object")
        }
        return object
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

private struct ValidationAIHTTPClient: AIHTTPClient {
    func bytes(for request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("""
            data: {"choices":[{"delta":{"content":"provider-ok"}}]}

            """.data(using: .utf8)!)
            continuation.yield("""
            data: [DONE]

            """.data(using: .utf8)!)
            continuation.finish()
        }
    }
}

/// Mutable reference to an Int for use as a sendable retention provider in tests.
private final class RetentionRef: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int

    var days: Int {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }

    init(days: Int) {
        self.storage = days
    }
}
