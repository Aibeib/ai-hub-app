import SwiftUI
import AIAgentHubCore

struct ChatHomeView: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var selectedSessionId: UUID?
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var streamingText = ""
    @State private var streamingIsActive = false
    @State private var searchQuery = ""
    @State private var exportPayload: ConversationExportPayload?
    @State private var lastFailedSend: FailedSend?
    @State private var editingMessage: MessageEditTarget?
    @State private var systemPromptDraft: SystemPromptDraft?
    @FocusState private var inputFocused: Bool

    private struct FailedSend: Equatable {
        let sessionId: UUID
        let message: String
        let errorDescription: String
    }

    struct MessageEditTarget: Identifiable, Equatable {
        let id = UUID()
        let sessionId: UUID
        let messageId: UUID
        let originalContent: String
    }

    struct SystemPromptDraft: Identifiable, Equatable {
        let id = UUID()
        let sessionId: UUID
        var content: String
    }

    private var visibleSessions: [ChatSessionRecord] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = runtime.sessions.filter { !$0.isArchived }
        guard !trimmed.isEmpty else { return all }

        // Match either the title or any message content.
        let messageMatches = Set(runtime.searchMessages(trimmed, limit: 200).map(\.sessionId))
        return all.filter { session in
            session.title.lowercased().contains(trimmed)
                || messageMatches.contains(session.id)
        }
    }

    private var selectedSession: ChatSessionRecord? {
        guard let id = selectedSessionId else { return nil }
        return runtime.sessions.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            sessionListPane
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)

            Divider().overlay(DS.Palette.separator)

            transcriptPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DS.Palette.surface)
        .alert(
            "Message failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: lastFailedSend
        ) { failed in
            Button("Retry") {
                Task { await retryFailedSend(failed) }
            }
            Button("Edit", role: .cancel) {
                draft = failed.message
            }
            Button("Dismiss", role: .destructive) {
                lastFailedSend = nil
            }
        } message: { failed in
            Text(failed.errorDescription)
        }
        .sheet(item: $exportPayload) { payload in
            ConversationExportView(payload: payload)
        }
        .sheet(item: $editingMessage) { target in
            MessageEditView(target: target) { newContent in
                handleMessageEdit(target: target, newContent: newContent)
            }
        }
        .sheet(item: $systemPromptDraft) { draft in
            SystemPromptEditorView(
                initial: draft.content,
                onSave: { newPrompt in
                    runtime.setSystemPrompt(draft.sessionId, prompt: newPrompt)
                }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if selectedSessionId == nil {
                selectedSessionId = runtime.restorableSessionId()
            }
        }
        .onChange(of: selectedSessionId) { _, newValue in
            runtime.rememberOpenSession(newValue)
        }
    }

    // MARK: - Session list pane

    private var sessionListPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top header with new chat button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conversations")
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text("\(visibleSessions.count) total")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                Spacer()
                Button {
                    let session = runtime.createSession()
                    selectedSessionId = session.id
                    inputFocused = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(DS.Palette.accentSoft)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.lg)
            .padding(.bottom, DS.Space.sm)

            // Search
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Palette.textTertiary)
                TextField("Search", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(DS.Typography.callout)
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(DS.Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(DS.Palette.border, lineWidth: 0.5)
            )
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.sm)

            // Session list
            ScrollView {
                LazyVStack(spacing: 2) {
                    if visibleSessions.isEmpty {
                        Text(searchQuery.isEmpty ? "No conversations yet." : "No matches.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.vertical, DS.Space.md)
                    } else {
                        ForEach(visibleSessions) { session in
                            SessionRow(
                                session: session,
                                isSelected: session.id == selectedSessionId,
                                preview: messagePreview(for: session),
                                onSelect: {
                                    withAnimation(DS.Motion.springSnappy) {
                                        selectedSessionId = session.id
                                    }
                                },
                                onPin: { runtime.togglePin(session.id) },
                                onDelete: {
                                    runtime.deleteSession(session.id)
                                    if selectedSessionId == session.id {
                                        selectedSessionId = nil
                                    }
                                }
                            )
                            .padding(.horizontal, DS.Space.xs)
                        }
                    }
                }
                .padding(.bottom, DS.Space.lg)
            }
        }
        .background(DS.Palette.surfaceRaised)
    }

    private func messagePreview(for session: ChatSessionRecord) -> String {
        let messages = runtime.chatRepository.messages(for: session.id)
        return messages.last?.content ?? "Start a conversation"
    }

    // MARK: - Transcript pane

    private var transcriptPane: some View {
        VStack(spacing: 0) {
            if let selectedSession {
                transcriptHeader(for: selectedSession)
                Divider().overlay(DS.Palette.separator)
                if !runtime.sessionHasAPIKey(selectedSession.id) {
                    MissingAPIKeyBanner(modelName: runtime.resolvedModelName(for: selectedSession.id))
                }
                transcriptScroll(for: selectedSession)
                inputBar(for: selectedSession)
            } else {
                DSEmptyState(
                    icon: "sparkles",
                    title: "A quiet place to think",
                    message: "Conversations are stored locally on your device. Third-party APIs only see redacted text — your raw notes stay here.",
                    action: ("Start a new conversation", {
                        let session = runtime.createSession()
                        selectedSessionId = session.id
                        inputFocused = true
                    })
                )
            }
        }
    }

    private func transcriptHeader(for session: ChatSessionRecord) -> some View {
        HStack(spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Palette.textPrimary)

                HStack(spacing: DS.Space.xs) {
                    if let modelName = currentModelName(for: session) {
                        Text(modelName)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    Text("·")
                        .foregroundStyle(DS.Palette.textTertiary)
                    Text(session.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                    let usage = runtime.tokenUsage(for: session.id)
                    if usage.promptTokens + usage.completionTokens > 0 {
                        Text("·")
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text("\(usage.promptTokens + usage.completionTokens) tokens")
                            .font(DS.Typography.captionSmall.monospacedDigit())
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                }
            }

            Spacer()

            Menu {
                Section("Switch model") {
                    ForEach(runtime.modelConfigs.filter(\.isEnabled)) { model in
                        Button {
                            runtime.bindModelToSession(session.id, modelId: model.id)
                        } label: {
                            Label(model.name, systemImage: model.id == session.modelConfigId ? "checkmark" : "")
                        }
                    }
                }

                Section {
                    Button {
                        systemPromptDraft = SystemPromptDraft(
                            sessionId: session.id,
                            content: session.systemPrompt ?? ""
                        )
                    } label: {
                        Label(
                            session.systemPrompt == nil ? "Set system prompt" : "Edit system prompt",
                            systemImage: "text.bubble"
                        )
                    }

                    Button {
                        Task { await regenerate(in: session) }
                    } label: {
                        Label("Regenerate last reply", systemImage: "arrow.clockwise")
                    }
                    .disabled(isSending || runtime.chatRepository.messages(for: session.id).isEmpty)

                    Button {
                        if let md = runtime.exportConversation(for: session.id, format: .markdown) {
                            exportPayload = ConversationExportPayload(format: .markdown, content: md, sessionTitle: session.title)
                        }
                    } label: {
                        Label("Export as Markdown", systemImage: "doc.richtext")
                    }
                    Button {
                        if let json = runtime.exportConversation(for: session.id, format: .json) {
                            exportPayload = ConversationExportPayload(format: .json, content: json, sessionTitle: session.title)
                        }
                    } label: {
                        Label("Export as JSON", systemImage: "curlybraces.square")
                    }
                }

                Section {
                    Button {
                        runtime.togglePin(session.id)
                    } label: {
                        Label(session.isPinned ? "Unpin" : "Pin", systemImage: session.isPinned ? "pin.slash" : "pin")
                    }
                    Button {
                        runtime.archiveSession(session.id)
                        selectedSessionId = nil
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    Button(role: .destructive) {
                        runtime.deleteSession(session.id)
                        selectedSessionId = nil
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
        .background(DS.Palette.surface)
    }

    private func currentModelName(for session: ChatSessionRecord) -> String? {
        guard let modelId = session.modelConfigId else { return nil }
        return runtime.modelConfigs.first { $0.id == modelId }?.name
    }

    private func transcriptScroll(for session: ChatSessionRecord) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                let messages = runtime.chatRepository.messages(for: session.id)
                LazyVStack(alignment: .leading, spacing: DS.Space.lg) {
                    if messages.isEmpty && !streamingIsActive {
                        FirstMessageHint()
                            .padding(.top, DS.Space.xxl)
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                onDelete: {
                                    runtime.deleteMessage(message.id, in: session.id)
                                },
                                onBranch: {
                                    if let branched = runtime.branchSession(from: session.id, atMessage: message.id) {
                                        selectedSessionId = branched.id
                                    }
                                },
                                onEdit: message.role == .user ? {
                                    editingMessage = MessageEditTarget(
                                        sessionId: session.id,
                                        messageId: message.id,
                                        originalContent: message.content
                                    )
                                } : nil
                            )
                                .id(message.id)
                        }

                        if streamingIsActive {
                            StreamingBubble(text: streamingText)
                                .id("__streaming__")
                        }
                    }
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.vertical, DS.Space.lg)
            }
            .background(DS.Palette.surface)
            .onChange(of: streamingText) { _, _ in
                withAnimation(.linear(duration: 0.12)) {
                    proxy.scrollTo("__streaming__", anchor: .bottom)
                }
            }
            .onChange(of: runtime.chatRepository.messages(for: session.id).count) { _, _ in
                if let last = runtime.chatRepository.messages(for: session.id).last {
                    withAnimation(DS.Motion.springSnappy) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func inputBar(for session: ChatSessionRecord) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(DS.Palette.separator)
            HStack(alignment: .bottom, spacing: DS.Space.sm) {
                HStack(alignment: .bottom, spacing: DS.Space.xs) {
                    TextField("Message AI Hub…", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(DS.Typography.body)
                        .lineLimit(1...6)
                        .focused($inputFocused)
                        .onSubmit { Task { await send(in: session) } }

                    if !draft.isEmpty {
                        Button {
                            draft = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(DS.Palette.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm + 2)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Palette.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(inputFocused ? DS.Palette.accent.opacity(0.6) : DS.Palette.border, lineWidth: inputFocused ? 1.5 : 0.5)
                        .animation(DS.Motion.easeOutFast, value: inputFocused)
                )

                Button {
                    if isSending {
                        runtime.cancelActiveGeneration()
                    } else {
                        Task { await send(in: session) }
                    }
                } label: {
                    Group {
                        if isSending {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .semibold))
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(isSending ? DS.Palette.danger : (canSend ? DS.Palette.textPrimary : DS.Palette.textTertiary))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isSending && !canSend)
                .animation(DS.Motion.easeOutFast, value: canSend)
                .animation(DS.Motion.easeOutFast, value: isSending)
            }
            .padding(DS.Space.md)
            .background(DS.Palette.surface)
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func send(in session: ChatSessionRecord) async {
        guard canSend else { return }
        let message = draft
        draft = ""
        await runGeneration(in: session) { orchestrator, model, buffer in
            try await orchestrator.sendUserMessage(
                message,
                in: session.id,
                using: model,
                tools: runtime.toolRegistry.definitions,
                streamingBuffer: buffer
            )
        } onError: { error in
            lastFailedSend = FailedSend(
                sessionId: session.id,
                message: message,
                errorDescription: error.localizedDescription
            )
            errorMessage = error.localizedDescription
        }
    }

    private func retryFailedSend(_ failed: FailedSend) async {
        guard let session = runtime.sessions.first(where: { $0.id == failed.sessionId }) else {
            lastFailedSend = nil
            return
        }
        lastFailedSend = nil
        await runGeneration(in: session) { orchestrator, model, buffer in
            try await orchestrator.sendUserMessage(
                failed.message,
                in: session.id,
                using: model,
                tools: runtime.toolRegistry.definitions,
                streamingBuffer: buffer
            )
        } onError: { error in
            lastFailedSend = FailedSend(
                sessionId: failed.sessionId,
                message: failed.message,
                errorDescription: error.localizedDescription
            )
            errorMessage = error.localizedDescription
        }
    }

    /// Apply an in-place edit to a user message. We update the content, drop everything that
    /// came after (those were responses to the old prompt and are now stale), and re-trigger
    /// generation so the assistant answers the corrected question.
    private func handleMessageEdit(target: MessageEditTarget, newContent: String) {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != target.originalContent else {
            return
        }
        runtime.updateMessageContent(target.messageId, in: target.sessionId, newContent: trimmed)
        runtime.deleteMessagesAfter(target.messageId, in: target.sessionId)

        // Re-run generation with the edited message as the last user turn.
        guard let session = runtime.sessions.first(where: { $0.id == target.sessionId }) else {
            return
        }
        Task {
            await runGeneration(in: session) { orchestrator, model, buffer in
                try await orchestrator.regenerateLastAssistantMessage(
                    in: session.id,
                    using: model,
                    tools: runtime.toolRegistry.definitions,
                    streamingBuffer: buffer
                )
            } onError: { error in
                errorMessage = error.localizedDescription
            }
        }
    }

    private func regenerate(in session: ChatSessionRecord) async {
        await runGeneration(in: session) { orchestrator, model, buffer in
            try await orchestrator.regenerateLastAssistantMessage(
                in: session.id,
                using: model,
                tools: runtime.toolRegistry.definitions,
                streamingBuffer: buffer
            )
        } onError: { error in
            // Don't refill draft for regenerate — there's no draft text to restore.
            errorMessage = error.localizedDescription
        }
    }

    private func runGeneration(
        in session: ChatSessionRecord,
        run: @escaping (ChatOrchestrator, ResolvedModelConfig, StreamingResponseBuffer) async throws -> String,
        onError: @escaping (Error) -> Void
    ) async {
        isSending = true
        streamingText = ""
        streamingIsActive = true
        defer {
            isSending = false
            streamingIsActive = false
            streamingText = ""
        }

        let buffer = StreamingResponseBuffer()
        let observerStream = await buffer.observe()
        let observerTask = Task {
            for await snapshot in observerStream {
                await MainActor.run {
                    streamingText = snapshot.text
                }
            }
        }

        let generationTask = Task<Void, Never> {
            do {
                let resolvedModel = try resolveModel(for: session)
                let aiService = try runtime.modelManager.makeService(for: resolvedModel)
                let orchestrator = ChatOrchestrator(
                    repository: runtime.chatRepository,
                    aiService: aiService,
                    redactor: PrivacyRedactor(),
                    contextBuilder: ContextBuilder(),
                    toolRegistry: runtime.toolRegistry,
                    privacyPreferences: runtime.privacyPreferences
                )
                _ = try await run(orchestrator, resolvedModel, buffer)
                await MainActor.run { runtime.refreshSessions() }
            } catch is CancellationError {
                // Generation was cancelled — partial message already persisted by the orchestrator.
                await MainActor.run { runtime.refreshSessions() }
            } catch {
                await MainActor.run { onError(error) }
            }
        }

        await runtime.generationTracker.register(generationTask)
        _ = await generationTask.value
        await runtime.generationTracker.clear()
        observerTask.cancel()
    }

    private func resolveModel(for session: ChatSessionRecord) throws -> ResolvedModelConfig {
        if let modelId = session.modelConfigId,
           let record = runtime.modelConfigs.first(where: { $0.id == modelId && $0.isEnabled }) {
            return try runtime.modelManager.resolve(record: record)
        }
        return try runtime.modelManager.resolveDefaultModel()
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let session: ChatSessionRecord
    let isSelected: Bool
    let preview: String
    let onSelect: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: DS.Space.sm) {
                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.accent)
                        .padding(.top, 4)
                } else {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 10, height: 10)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(DS.Typography.callout.weight(.medium))
                        .foregroundStyle(isSelected ? DS.Palette.textPrimary : DS.Palette.textPrimary.opacity(0.92))
                        .lineLimit(1)

                    Text(preview)
                        .font(DS.Typography.captionSmall)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text(session.updatedAt, style: .relative)
                    .font(DS.Typography.captionSmall)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DS.Space.sm + 2)
            .padding(.vertical, DS.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(isSelected ? DS.Palette.accentSoft : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onPin()
            } label: {
                Label(session.isPinned ? "Unpin" : "Pin", systemImage: session.isPinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Message bubbles

private struct MessageBubble: View {
    let message: ChatMessageDTO
    var onDelete: (() -> Void)? = nil
    var onBranch: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    var body: some View {
        Group {
            switch message.role {
            case .user:
                UserBubble(message: message)
            case .assistant:
                AssistantBubble(text: message.content, timestamp: message.timestamp)
            case .tool:
                ToolBubble(content: message.content)
            case .system:
                SystemBubble(content: message.content)
            }
        }
        .contextMenu {
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = message.content
                #elseif canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                #endif
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if message.role == .user, let onEdit {
                Button(action: onEdit) {
                    Label("Edit message", systemImage: "pencil")
                }
            }
            if let onBranch {
                Button(action: onBranch) {
                    Label("Branch from here", systemImage: "arrow.triangle.branch")
                }
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete message", systemImage: "trash")
                }
            }
        }
    }
}

private struct UserBubble: View {
    let message: ChatMessageDTO

    var body: some View {
        HStack {
            Spacer(minLength: 64)
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.content)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.userBubbleText)
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm + 2)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .fill(DS.Palette.userBubble)
                    )
                    .textSelection(.enabled)

                Text(message.timestamp, style: .time)
                    .font(DS.Typography.captionSmall)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }
}

private struct AssistantBubble: View {
    let text: String
    let timestamp: Date

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            AssistantGlyph()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: DS.Space.xs) {
                    Text("Assistant")
                        .font(DS.Typography.subheadline)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Text("·")
                        .foregroundStyle(DS.Palette.textTertiary)
                    Text(timestamp, style: .time)
                        .font(DS.Typography.captionSmall)
                        .foregroundStyle(DS.Palette.textTertiary)
                }

                Text(text)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm + 2)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .fill(DS.Palette.assistantBubble)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .stroke(DS.Palette.border, lineWidth: 0.5)
                    )
            }
            Spacer(minLength: 64)
        }
    }
}

private struct StreamingBubble: View {
    let text: String
    @State private var phase: Double = 0

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            AssistantGlyph()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: DS.Space.xs) {
                    Text("Assistant")
                        .font(DS.Typography.subheadline)
                        .foregroundStyle(DS.Palette.textSecondary)
                    DSStatusDot(status: .live, animated: true)
                    Text("typing")
                        .font(DS.Typography.captionSmall)
                        .foregroundStyle(DS.Palette.textTertiary)
                }

                Text(text.isEmpty ? "…" : text)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineSpacing(4)
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm + 2)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .fill(DS.Palette.assistantBubble)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .stroke(DS.Palette.accent.opacity(0.35), lineWidth: 1)
                    )
            }
            Spacer(minLength: 64)
        }
    }
}

private struct ToolBubble: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(DS.Palette.warning.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Palette.warning)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tool result")
                    .font(DS.Typography.subheadline)
                    .foregroundStyle(DS.Palette.warning)
                Text(content)
                    .font(DS.Typography.mono)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(DS.Space.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(DS.Palette.warning.opacity(0.08))
                    )
                    .textSelection(.enabled)
            }
            Spacer(minLength: 64)
        }
    }
}

private struct SystemBubble: View {
    let content: String

    var body: some View {
        HStack {
            Spacer()
            Text(content)
                .font(DS.Typography.captionSmall)
                .foregroundStyle(DS.Palette.textTertiary)
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(DS.Palette.separator.opacity(0.5))
                )
            Spacer()
        }
    }
}

private struct AssistantGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DS.Palette.accentSoft)
                .frame(width: 28, height: 28)
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Palette.accent)
        }
    }
}

// MARK: - First-message hint

private struct FirstMessageHint: View {
    var body: some View {
        VStack(spacing: DS.Space.md) {
            ZStack {
                Circle()
                    .fill(DS.Palette.accentSoft)
                    .frame(width: 64, height: 64)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(DS.Palette.accent)
            }
            Text("Ask me anything")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Palette.textPrimary)
            Text("Your message will be redacted for privacy before being sent to the model. Tool calls always ask for approval.")
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Conversation export sheet

struct ConversationExportPayload: Identifiable {
    let id = UUID()
    let format: ConversationExportFormat
    let content: String
    let sessionTitle: String
}

private struct ConversationExportView: View {
    let payload: ConversationExportPayload
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(payload.content)
                    .font(DS.Typography.mono)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(DS.Space.md)
            }
            .background(DS.Palette.surface)
            .navigationTitle("\(payload.format.displayName) export")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: payload.content,
                        preview: SharePreview(
                            "\(payload.sessionTitle).\(payload.format.fileExtension)"
                        )
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Message edit sheet

private struct MessageEditView: View {
    let target: ChatHomeView.MessageEditTarget
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String

    init(target: ChatHomeView.MessageEditTarget, onSave: @escaping (String) -> Void) {
        self.target = target
        self.onSave = onSave
        _content = State(initialValue: target.originalContent)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Editing will discard the assistant reply and re-run the prompt.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)

                TextEditor(text: $content)
                    .font(DS.Typography.body)
                    .scrollContentBackground(.hidden)
                    .padding(DS.Space.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(DS.Palette.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(DS.Palette.border, lineWidth: 0.5)
                    )
                    .frame(minHeight: 200)
            }
            .padding(DS.Space.md)
            .background(DS.Palette.surface)
            .navigationTitle("Edit message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & regenerate") {
                        onSave(content)
                        dismiss()
                    }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - System prompt editor

private struct SystemPromptEditorView: View {
    let initial: String
    let onSave: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String

    init(initial: String, onSave: @escaping (String?) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _content = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    Text("System prompt steers the assistant's behaviour for this conversation. Leave it blank to use the model's defaults.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.top, DS.Space.sm)

                    TextEditor(text: $content)
                        .font(DS.Typography.body)
                        .scrollContentBackground(.hidden)
                        .padding(DS.Space.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .fill(DS.Palette.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .stroke(DS.Palette.border, lineWidth: 0.5)
                        )
                        .frame(minHeight: 220)
                        .padding(.horizontal, DS.Space.md)

                    Text("Presets".uppercased())
                        .font(DS.Typography.captionSmall)
                        .tracking(1.6)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.top, DS.Space.sm)

                    LazyVStack(spacing: DS.Space.xs) {
                        ForEach(SystemPromptPreset.allCases) { preset in
                            Button {
                                content = preset.prompt
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.title)
                                        .font(DS.Typography.callout.weight(.medium))
                                        .foregroundStyle(DS.Palette.textPrimary)
                                    Text(preset.summary)
                                        .font(DS.Typography.captionSmall)
                                        .foregroundStyle(DS.Palette.textSecondary)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DS.Space.sm + 2)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                        .fill(DS.Palette.surfaceElevated)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                        .stroke(DS.Palette.border, lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DS.Space.md)
                    .padding(.bottom, DS.Space.lg)
                }
            }
            .background(DS.Palette.surface)
            .navigationTitle("System prompt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear", role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Missing API key banner

private struct MissingAPIKeyBanner: View {
    let modelName: String?

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.sm) {
            Image(systemName: "key.slash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.Palette.warning)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("API key missing")
                    .font(DS.Typography.subheadline)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(message)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Text("Open Models")
                .font(DS.Typography.captionSmall.weight(.semibold))
                .foregroundStyle(DS.Palette.warning)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.sm + 2)
        .background(DS.Palette.warning.opacity(0.08))
        .overlay(
            Rectangle()
                .fill(DS.Palette.warning.opacity(0.35))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var message: String {
        if let modelName {
            "Add your provider key to use \(modelName) — or pick a different model from the menu."
        } else {
            "Set up a model from the Models tab before sending messages."
        }
    }
}
