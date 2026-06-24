import SwiftUI
import AIAgentHubCore

struct ChatHomeView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.appLanguage) private var language
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
    @State private var isShowingSessionList = false
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

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        Group {
            if isCompact {
                compactBody
            } else {
                regularBody
            }
        }
        .background(DS.Palette.surface)
        .alert(
            language[.alertMessageFailedTitle],
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: lastFailedSend
        ) { failed in
            Button(language[.actionRetry]) {
                Task { await retryFailedSend(failed) }
            }
            Button(language == .zh ? "编辑" : "Edit", role: .cancel) {
                draft = failed.message
            }
            Button(language[.actionDismiss], role: .destructive) {
                lastFailedSend = nil
            }
        } message: { failed in
            Text(failed.errorDescription)
        }
        .sheet(item: $exportPayload) { payload in
            ConversationExportView(payload: payload, language: language)
        }
        .sheet(item: $editingMessage) { target in
            MessageEditView(target: target, language: language) { newContent in
                handleMessageEdit(target: target, newContent: newContent)
            }
        }
        .sheet(item: $systemPromptDraft) { draft in
            SystemPromptEditorView(
                initial: draft.content,
                language: language,
                onSave: { newPrompt in
                    runtime.setSystemPrompt(draft.sessionId, prompt: newPrompt)
                }
            )
        }
        .sheet(isPresented: $isShowingSessionList) {
            NavigationStack {
                sessionListPane(forSheet: true)
                    .navigationTitle(language[.chatHistory])
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(language[.actionDone]) {
                                isShowingSessionList = false
                            }
                        }
                    }
            }
        }
        .onAppear {
            if selectedSessionId == nil {
                selectedSessionId = runtime.restorableSessionId()
            }
        }
        .onChange(of: selectedSessionId) { _, newValue in
            runtime.rememberOpenSession(newValue)
        }
    }

    // MARK: - Compact (iPhone) layout

    private var compactBody: some View {
        VStack(spacing: 0) {
            compactTopBar
            Divider().overlay(DS.Palette.separator)

            if let selectedSession {
                if !runtime.sessionHasAPIKey(selectedSession.id) {
                    MissingAPIKeyBanner(
                        modelName: runtime.resolvedModelName(for: selectedSession.id),
                        language: language
                    )
                }
                transcriptScroll(for: selectedSession)
                inputBar(for: selectedSession)
            } else {
                Spacer(minLength: 0)
                emptyChatHero
                Spacer(minLength: 0)
            }
        }
    }

    private var compactTopBar: some View {
        HStack(spacing: DS.Space.sm) {
            Button {
                isShowingSessionList = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(DS.Palette.surfaceElevated)
                    )
                    .overlay(
                        Circle().stroke(DS.Palette.border, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedSession?.title ?? language[.chatTitle])
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                if let session = selectedSession,
                   let modelName = currentModelName(for: session) {
                    Text(modelName)
                        .font(DS.Typography.captionSmall.monospacedDigit())
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }

            Spacer()

            // New conversation
            Button {
                let session = runtime.createSession(title: language[.chatNewConversation])
                selectedSessionId = session.id
                inputFocused = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(DS.Palette.accentSoft)
                    )
            }
            .buttonStyle(.plain)

            if selectedSession != nil {
                sessionMenu(for: selectedSession!)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(DS.Palette.surface)
    }

    private var emptyChatHero: some View {
        DSEmptyState(
            icon: "sparkles",
            title: language[.sparklesQuietTitle],
            message: language[.sparklesQuietSubtitle],
            action: (language[.sparklesCTA], {
                let session = runtime.createSession(title: language[.chatNewConversation])
                selectedSessionId = session.id
                inputFocused = true
            })
        )
    }

    // MARK: - Regular (iPad / Mac) layout

    private var regularBody: some View {
        HStack(spacing: 0) {
            sessionListPane(forSheet: false)
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)

            Divider().overlay(DS.Palette.separator)

            transcriptPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Session list pane

    private func sessionListPane(forSheet: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !forSheet {
                // Top header with new chat button (only on regular layout; sheet has its own nav bar)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language[.chatHistory])
                            .font(DS.Typography.title)
                            .foregroundStyle(DS.Palette.textPrimary)
                        Text(String(format: language[.chatTotalCount], visibleSessions.count))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    Spacer()
                    Button {
                        let session = runtime.createSession(title: language[.chatNewConversation])
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
            }

            // Search
            HStack(spacing: DS.Space.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Palette.textTertiary)
                TextField(language[.chatSearchPlaceholder], text: $searchQuery)
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
            .padding(.top, forSheet ? DS.Space.sm : 0)
            .padding(.bottom, DS.Space.sm)

            // New conversation (sheet only — header on regular layout already has this)
            if forSheet {
                Button {
                    let session = runtime.createSession(title: language[.chatNewConversation])
                    selectedSessionId = session.id
                    isShowingSessionList = false
                    inputFocused = true
                } label: {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(DS.Palette.accent)
                        Text(language[.chatNewConversation])
                            .font(DS.Typography.callout.weight(.semibold))
                            .foregroundStyle(DS.Palette.accent)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm + 2)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .fill(DS.Palette.accentSoft)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.sm)
            }

            // Session list
            ScrollView {
                LazyVStack(spacing: 2, pinnedViews: [.sectionHeaders]) {
                    if visibleSessions.isEmpty {
                        Text(searchQuery.isEmpty
                             ? language[.chatNoConversationsYet]
                             : language[.chatNoSearchMatches])
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.vertical, DS.Space.md)
                    } else {
                        let groups = SessionDateGrouper().group(visibleSessions)
                        // Compute previews in a single pass before the ForEach. Each
                        // `messages(for:)` call is a full SwiftData fetch; doing it
                        // inline per row was the second-biggest scroll cost after the
                        // transcript bubbles.
                        let previews = visibleSessions.reduce(into: [UUID: String]()) {
                            $0[$1.id] = messagePreview(for: $1)
                        }
                        ForEach(groups, id: \.bucket) { group in
                            Section {
                                ForEach(group.sessions) { session in
                                    SessionRow(
                                        session: session,
                                        isSelected: session.id == selectedSessionId,
                                        preview: previews[session.id] ?? language[.chatStartHint],
                                        language: language,
                                        onSelect: {
                                            withAnimation(DS.Motion.springSnappy) {
                                                selectedSessionId = session.id
                                                if forSheet {
                                                    isShowingSessionList = false
                                                }
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
                                    .equatable()
                                    .padding(.horizontal, DS.Space.xs)
                                }
                            } header: {
                                SessionGroupHeader(title: group.bucket.title)
                            }
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
        return messages.last?.content ?? language[.chatStartHint]
    }

    // MARK: - Transcript pane (regular layout)

    private var transcriptPane: some View {
        VStack(spacing: 0) {
            if let selectedSession {
                transcriptHeader(for: selectedSession)
                Divider().overlay(DS.Palette.separator)
                if !runtime.sessionHasAPIKey(selectedSession.id) {
                    MissingAPIKeyBanner(
                        modelName: runtime.resolvedModelName(for: selectedSession.id),
                        language: language
                    )
                }
                transcriptScroll(for: selectedSession)
                inputBar(for: selectedSession)
            } else {
                emptyChatHero
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
                    RelativeTimestamp(date: session.createdAt)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                    let usage = runtime.tokenUsage(for: session.id)
                    if usage.promptTokens + usage.completionTokens > 0 {
                        Text("·")
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text("\(usage.promptTokens + usage.completionTokens) \(language[.transcriptTokensSuffix])")
                            .font(DS.Typography.captionSmall.monospacedDigit())
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                }
            }

            Spacer()

            sessionMenu(for: session)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.lg)
        .background(DS.Palette.surface)
    }

    /// Per-session "···" menu, shared by both compact and regular layouts.
    @ViewBuilder
    private func sessionMenu(for session: ChatSessionRecord) -> some View {
        Menu {
            Section(language[.actionSwitchModel]) {
                ForEach(runtime.modelConfigs.filter(\.isEnabled)) { model in
                    Button {
                        runtime.bindModelToSession(session.id, modelId: model.id)
                    } label: {
                        Label(
                            "\(model.name) · \(model.modelName)",
                            systemImage: model.id == session.modelConfigId ? "checkmark" : ""
                        )
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
                        session.systemPrompt == nil
                            ? language[.actionSetSystemPrompt]
                            : language[.actionEditSystemPrompt],
                        systemImage: "text.bubble"
                    )
                }

                Button {
                    Task { await regenerate(in: session) }
                } label: {
                    Label(language[.actionRegenerate], systemImage: "arrow.clockwise")
                }
                .disabled(isSending || runtime.chatRepository.messages(for: session.id).isEmpty)

                Button {
                    if let md = runtime.exportConversation(for: session.id, format: .markdown) {
                        exportPayload = ConversationExportPayload(format: .markdown, content: md, sessionTitle: session.title)
                    }
                } label: {
                    Label(language[.actionExportMarkdown], systemImage: "doc.richtext")
                }
                Button {
                    if let json = runtime.exportConversation(for: session.id, format: .json) {
                        exportPayload = ConversationExportPayload(format: .json, content: json, sessionTitle: session.title)
                    }
                } label: {
                    Label(language[.actionExportJSON], systemImage: "curlybraces.square")
                }
            }

            Section {
                Button {
                    runtime.togglePin(session.id)
                } label: {
                    Label(
                        session.isPinned ? language[.actionUnpin] : language[.actionPin],
                        systemImage: session.isPinned ? "pin.slash" : "pin"
                    )
                }
                Button {
                    runtime.archiveSession(session.id)
                    selectedSessionId = nil
                } label: {
                    Label(language[.actionArchive], systemImage: "archivebox")
                }
                Button(role: .destructive) {
                    runtime.deleteSession(session.id)
                    selectedSessionId = nil
                } label: {
                    Label(language[.actionDelete], systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: 36, height: 36)
        }
    }

    private func currentModelName(for session: ChatSessionRecord) -> String? {
        guard let modelId = session.modelConfigId else { return nil }
        return runtime.modelConfigs.first { $0.id == modelId }?.name
    }

    private func transcriptScroll(for session: ChatSessionRecord) -> some View {
        ScrollViewReader { proxy in
            // Pull the message list once per body invocation. The repository call is a full
            // SwiftData fetch — calling it inside ForEach + multiple onChange closures (as
            // before) re-ran it 3-4× per scroll tick and was the dominant frame-drop source.
            let messages = runtime.chatRepository.messages(for: session.id)
            let messageCount = messages.count
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.lg) {
                    if messages.isEmpty && !streamingIsActive {
                        FirstMessageHint(language: language)
                            .padding(.top, DS.Space.xxl)
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                language: language,
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
                                } : nil,
                                onToggleBookmark: {
                                    runtime.toggleBookmark(message.id, in: session.id)
                                }
                            )
                                .equatable()
                                .id(message.id)
                        }

                        if streamingIsActive {
                            StreamingBubble(
                                text: streamingText,
                                modelName: runtime.resolvedModelName(for: session.id)
                                    ?? runtime.modelManager.defaultModel()?.name,
                                language: language
                            )
                                .id("__streaming__")
                        }
                    }
                }
                .padding(.horizontal, isCompact ? DS.Space.md : DS.Space.xl)
                .padding(.vertical, DS.Space.lg)
            }
            .background(DS.Palette.surface)
            .onChange(of: streamingText) { _, _ in
                withAnimation(.linear(duration: 0.12)) {
                    proxy.scrollTo("__streaming__", anchor: .bottom)
                }
            }
            .onChange(of: messageCount) { _, _ in
                if let lastId = messages.last?.id {
                    withAnimation(DS.Motion.springSnappy) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func inputBar(for session: ChatSessionRecord) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(DS.Palette.separator)

            // Slash command suggestions float above the input field when the user has typed `/`
            let suggestions = SlashCommandParser.suggestions(forPrefix: draft)
            if !suggestions.isEmpty && inputFocused {
                SlashCommandSuggestions(
                    commands: suggestions,
                    onPick: { command in
                        draft = command.prefix + " "
                    }
                )
                .padding(.horizontal, DS.Space.md)
                .padding(.top, DS.Space.xs)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: DS.Space.sm) {
                HStack(alignment: .bottom, spacing: DS.Space.xs) {
                    TextField(language[.chatInputPlaceholder], text: $draft, axis: .vertical)
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
                            .fill(isSending ? DS.Palette.danger : (canSend ? DS.Palette.accent : DS.Palette.textTertiary))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isSending && !canSend)
                .animation(DS.Motion.easeOutFast, value: canSend)
                .animation(DS.Motion.easeOutFast, value: isSending)
            }
            .padding(DS.Space.md)
            .background(DS.Palette.surface)

            // Token estimate bar
            let estimate = TokenEstimator.estimateTokens(in: draft)
            if estimate > 0 {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.textTertiary)

                    Text("~\(estimate) tokens → ")
                        .font(DS.Typography.captionSmall.monospacedDigit())
                        .foregroundStyle(DS.Palette.textTertiary)

                    if let modelRecord = resolvedModel(for: session),
                       estimate >= modelRecord.maxTokens {
                        Text(language == .zh
                             ? "超出 \(modelRecord.maxTokens) 上限"
                             : "Exceeds \(modelRecord.maxTokens) limit")
                            .font(DS.Typography.captionSmall.weight(.semibold))
                            .foregroundStyle(DS.Palette.danger)
                    } else if let modelRecord = resolvedModel(for: session),
                              Double(estimate) >= Double(modelRecord.maxTokens) * 0.75 {
                        Text(language == .zh
                             ? "已用 \(Int(Double(estimate) / Double(modelRecord.maxTokens) * 100))%"
                             : "\(Int(Double(estimate) / Double(modelRecord.maxTokens) * 100))% of budget")
                            .font(DS.Typography.captionSmall)
                            .foregroundStyle(DS.Palette.warning)
                    } else {
                        Text(language == .zh ? "在预算内" : "within model budget")
                            .font(DS.Typography.captionSmall)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }

                    Spacer()
                }
                .padding(.horizontal, isCompact ? DS.Space.md : DS.Space.xl)
                .padding(.bottom, DS.Space.xs)
                .transition(.opacity)
            }
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func send(in session: ChatSessionRecord) async {
        guard canSend else { return }
        let raw = draft

        // Intercept slash commands before they ever reach the model.
        if case let .command(command, args) = SlashCommandParser.parse(raw) {
            await handle(command: command, args: args, in: session)
            return
        }

        draft = ""
        await runGeneration(in: session) { orchestrator, model, buffer in
            try await orchestrator.sendUserMessage(
                raw,
                in: session.id,
                using: model,
                tools: runtime.toolRegistry.definitions,
                streamingBuffer: buffer
            )
        } onError: { error in
            let mapped = ErrorMessageMapper.message(for: error)
            lastFailedSend = FailedSend(
                sessionId: session.id,
                message: raw,
                errorDescription: mapped.detail
            )
            errorMessage = mapped.detail
        }
    }

    /// Resolve a slash command.
    private func handle(command: SlashCommand, args: String, in session: ChatSessionRecord) async {
        switch command {
        case .system:
            if args.isEmpty {
                systemPromptDraft = SystemPromptDraft(
                    sessionId: session.id,
                    content: session.systemPrompt ?? ""
                )
            } else {
                runtime.setSystemPrompt(session.id, prompt: args)
            }
            draft = ""

        case .preset:
            systemPromptDraft = SystemPromptDraft(
                sessionId: session.id,
                content: session.systemPrompt ?? ""
            )
            draft = ""

        case .clear:
            for message in runtime.chatRepository.messages(for: session.id) {
                runtime.deleteMessage(message.id, in: session.id)
            }
            draft = ""

        case .code:
            let parts = args.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let language: String
            let body: String
            if parts.count == 2 {
                language = String(parts[0])
                body = String(parts[1])
            } else {
                language = ""
                body = args
            }
            let fence = "```\(language)\n\(body)\n```"
            draft = fence

        case .branch:
            guard let lastAssistant = runtime.chatRepository.messages(for: session.id)
                .reversed()
                .first(where: { $0.role == .assistant }) else {
                errorMessage = self.language == .zh ? "还没有可分支的内容。" : "Nothing to branch from yet."
                return
            }
            if let branched = runtime.branchSession(from: session.id, atMessage: lastAssistant.id) {
                selectedSessionId = branched.id
            }
            draft = ""

        case .help:
            errorMessage = SlashCommand.allCases
                .map { "\($0.usage) — \($0.summary)" }
                .joined(separator: "\n")
            draft = ""
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
            let mapped = ErrorMessageMapper.message(for: error)
            lastFailedSend = FailedSend(
                sessionId: failed.sessionId,
                message: failed.message,
                errorDescription: mapped.detail
            )
            errorMessage = mapped.detail
        }
    }

    private func handleMessageEdit(target: MessageEditTarget, newContent: String) {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != target.originalContent else {
            return
        }
        runtime.updateMessageContent(target.messageId, in: target.sessionId, newContent: trimmed)
        runtime.deleteMessagesAfter(target.messageId, in: target.sessionId)

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
                errorMessage = ErrorMessageMapper.message(for: error).detail
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
            errorMessage = ErrorMessageMapper.message(for: error).detail
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
        let observerTask = Task { @MainActor in
            for await snapshot in observerStream {
                streamingText = snapshot.text
            }
        }

        // The orchestrator calls into `runtime.chatRepository` (a SwiftData-backed @MainActor
        // type) from inside the streaming for-await loop. SwiftData's main `ModelContext` is
        // not thread-safe, so the whole task must stay pinned to MainActor — otherwise the
        // first `repository.appendMessage` after a network event crashes the app.
        let generationTask = Task<Void, Never> { @MainActor in
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
                runtime.refreshSessions()
            } catch is CancellationError {
                runtime.refreshSessions()
            } catch {
                onError(error)
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

    private func resolvedModel(for session: ChatSessionRecord) -> ModelConfigRecord? {
        if let id = session.modelConfigId,
           let record = runtime.modelConfigs.first(where: { $0.id == id && $0.isEnabled }) {
            return record
        }
        return runtime.modelConfigs.first { $0.isDefault && $0.isEnabled }
            ?? runtime.modelConfigs.first { $0.isEnabled }
    }
}

// MARK: - Session row

private struct SessionRow: View, Equatable {
    let session: ChatSessionRecord
    let isSelected: Bool
    let preview: String
    let language: AppLanguage
    let onSelect: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    nonisolated static func == (lhs: SessionRow, rhs: SessionRow) -> Bool {
        lhs.session.id == rhs.session.id
            && lhs.session.title == rhs.session.title
            && lhs.session.isPinned == rhs.session.isPinned
            && lhs.session.updatedAt == rhs.session.updatedAt
            && lhs.isSelected == rhs.isSelected
            && lhs.preview == rhs.preview
            && lhs.language == rhs.language
    }

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

                RelativeTimestamp(date: session.updatedAt)
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
                Label(
                    session.isPinned ? language[.actionUnpin] : language[.actionPin],
                    systemImage: session.isPinned ? "pin.slash" : "pin"
                )
            }
            Button(role: .destructive, action: onDelete) {
                Label(language[.actionDelete], systemImage: "trash")
            }
        }
    }
}

// MARK: - Message bubbles

/// Equatable so SwiftUI can skip re-evaluating bubbles whose underlying message hasn't
/// changed. The bubble owns no internal state worth tracking — equality on message id
/// + content + bookmark covers every visible difference. Without this, every scroll tick
/// or streaming token causes the whole transcript's bubbles to re-evaluate their body.
private struct MessageBubble: View, Equatable {
    let message: ChatMessageDTO
    let language: AppLanguage
    var onDelete: (() -> Void)? = nil
    var onBranch: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onToggleBookmark: (() -> Void)? = nil

    nonisolated static func == (lhs: MessageBubble, rhs: MessageBubble) -> Bool {
        lhs.message.id == rhs.message.id
            && lhs.message.content == rhs.message.content
            && lhs.message.isBookmarked == rhs.message.isBookmarked
            && lhs.language == rhs.language
    }

    var body: some View {
        Group {
            switch message.role {
            case .user:
                UserBubble(message: message)
            case .assistant:
                AssistantBubble(text: message.content, timestamp: message.timestamp, language: language)
            case .tool:
                ToolBubble(content: message.content, language: language)
            case .system:
                SystemBubble(content: message.content)
            }
        }
        .overlay(alignment: .topLeading) {
            if message.isBookmarked {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.accent)
                    .padding(6)
                    .background(
                        Circle().fill(DS.Palette.accentSoft)
                    )
                    .offset(x: -2, y: -2)
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
                Label(language[.actionCopy], systemImage: "doc.on.doc")
            }
            if let onToggleBookmark {
                Button(action: onToggleBookmark) {
                    Label(
                        message.isBookmarked ? language[.actionRemoveBookmark] : language[.actionBookmark],
                        systemImage: message.isBookmarked ? "bookmark.slash" : "bookmark"
                    )
                }
            }
            if message.role == .user, let onEdit {
                Button(action: onEdit) {
                    Label(language[.actionEditMessage], systemImage: "pencil")
                }
            }
            if let onBranch {
                Button(action: onBranch) {
                    Label(language[.actionBranchHere], systemImage: "arrow.triangle.branch")
                }
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label(language[.actionDeleteMessage], systemImage: "trash")
                }
            }
        }
    }
}

private struct UserBubble: View {
    let message: ChatMessageDTO

    var body: some View {
        HStack {
            Spacer(minLength: 48)
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

                RelativeTimestamp(date: message.timestamp)
                    .font(DS.Typography.captionSmall)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }
}

private struct AssistantBubble: View {
    let text: String
    let timestamp: Date
    let language: AppLanguage
    // Pre-parse markdown segments once at init. Calling `MessageSegmentParser.parse(text)`
    // from a computed property re-runs on every body recompute — and SwiftUI invalidates
    // `body` whenever an ancestor's state changes (sidebar toggle, streamingText tick).
    // For long assistant replies this was the biggest scroll-frame cost.
    private let segments: [MessageSegment]

    init(text: String, timestamp: Date, language: AppLanguage) {
        self.text = text
        self.timestamp = timestamp
        self.language = language
        self.segments = MessageSegmentParser.parse(text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            AssistantGlyph()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: DS.Space.xs) {
                    Text(language[.transcriptAssistantRole])
                        .font(DS.Typography.subheadline)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Text("·")
                        .foregroundStyle(DS.Palette.textTertiary)
                    RelativeTimestamp(date: timestamp)
                        .font(DS.Typography.captionSmall)
                        .foregroundStyle(DS.Palette.textTertiary)
                }

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        switch segment {
                        case let .inline(content):
                            InlineMarkdownText(content: content)
                        case let .code(language, body):
                            CodeBlockView(language: language, code: body)
                        }
                    }
                }
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
            Spacer(minLength: 32)
        }
    }
}

private struct StreamingBubble: View {
    let text: String
    var modelName: String? = nil
    let language: AppLanguage
    @State private var phase: Double = 0

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            AssistantGlyph()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: DS.Space.xs) {
                    Text(language[.transcriptAssistantRole])
                        .font(DS.Typography.subheadline)
                        .foregroundStyle(DS.Palette.textSecondary)
                    if let modelName {
                        Text("·")
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text(modelName)
                            .font(DS.Typography.captionSmall.monospacedDigit())
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    DSStatusDot(status: .live, animated: true)
                    Text(language[.transcriptTypingLabel])
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
            Spacer(minLength: 32)
        }
    }
}

private struct ToolBubble: View {
    let content: String
    let language: AppLanguage

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
                Text(language[.transcriptToolResult])
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
            Spacer(minLength: 32)
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
    let language: AppLanguage

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
            Text(language[.transcriptFirstHintTitle])
                .font(DS.Typography.title)
                .foregroundStyle(DS.Palette.textPrimary)
            Text(language[.transcriptFirstHintSubtitle])
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
    let language: AppLanguage
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
                    Button(language[.actionDone]) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: payload.content,
                        preview: SharePreview(
                            "\(payload.sessionTitle).\(payload.format.fileExtension)"
                        )
                    ) {
                        Label(language[.actionShare], systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

// MARK: - Message edit sheet

private struct MessageEditView: View {
    let target: ChatHomeView.MessageEditTarget
    let language: AppLanguage
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String

    init(target: ChatHomeView.MessageEditTarget, language: AppLanguage, onSave: @escaping (String) -> Void) {
        self.target = target
        self.language = language
        self.onSave = onSave
        _content = State(initialValue: target.originalContent)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text(language == .zh
                     ? "编辑后会丢弃之前的助手回复，并重新生成。"
                     : "Editing will discard the assistant reply and re-run the prompt.")
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
            .navigationTitle(language[.actionEditMessage])
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language[.actionCancel]) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language == .zh ? "保存并重新生成" : "Save & regenerate") {
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
    let language: AppLanguage
    let onSave: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String

    init(initial: String, language: AppLanguage, onSave: @escaping (String?) -> Void) {
        self.initial = initial
        self.language = language
        self.onSave = onSave
        _content = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    Text(language[.kSystemPromptHint])
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

                    Text(language[.kPresetsTitle].uppercased())
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
            .navigationTitle(language[.actionSetSystemPrompt])
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language[.actionCancel]) { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(language[.actionClear], role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language[.actionSave]) {
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
    let language: AppLanguage

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openModelsTab, object: nil)
        } label: {
            HStack(alignment: .center, spacing: DS.Space.sm) {
                Image(systemName: "key.slash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Palette.warning)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(language[.bannerAPIKeyMissingTitle])
                        .font(DS.Typography.subheadline)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(messageText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Text(language[.bannerAPIKeyMissingCTA])
                    .font(DS.Typography.captionSmall.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(DS.Palette.warning)
                    )
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.sm + 2)
            .background(DS.Palette.warning.opacity(0.12))
            .overlay(
                Rectangle()
                    .fill(DS.Palette.warning.opacity(0.35))
                    .frame(height: 0.5),
                alignment: .bottom
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var messageText: String {
        if let modelName {
            return String(format: language[.bannerAPIKeyMissingBodyForModel], modelName)
        } else {
            return language[.bannerAPIKeyMissingBodyGeneric]
        }
    }
}

// MARK: - Markdown segment views

/// Render inline markdown — bold, italic, links, inline code — using Apple's built-in parser.
/// Fenced code blocks are intentionally NOT handled here; they come through CodeBlockView.
private struct InlineMarkdownText: View {
    let content: String

    private var attributed: AttributedString {
        // `.full` interprets paragraph breaks; that fits multi-line inline text from LLMs better
        // than the default which collapses newlines.
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: content, options: options))
            ?? AttributedString(content)
    }

    var body: some View {
        Text(attributed)
            .font(DS.Typography.body)
            .foregroundStyle(DS.Palette.textPrimary)
            .lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var copied = false

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty ?? true ? "code" : language!).uppercased())
                    .font(DS.Typography.captionSmall)
                    .tracking(1.4)
                    .foregroundStyle(DS.Palette.textTertiary)
                Spacer()
                Button {
                    copy()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                        Text(copied ? "Copied" : "Copy")
                            .font(DS.Typography.captionSmall.weight(.medium))
                    }
                    .foregroundStyle(copied ? DS.Palette.positive : DS.Palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.Space.sm + 2)
            .padding(.vertical, 6)
            .background(DS.Palette.surface.opacity(0.6))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(DS.Typography.mono)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .textSelection(.enabled)
                    .padding(DS.Space.sm + 2)
            }
        }
        .background(DS.Palette.surfaceElevated.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(DS.Palette.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    var body: some View {
        bodyView
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif
        withAnimation(DS.Motion.springSnappy) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(DS.Motion.springSnappy) { copied = false }
            }
        }
    }
}

// MARK: - Slash command suggestions popover

private struct SlashCommandSuggestions: View {
    let commands: [SlashCommand]
    let onPick: (SlashCommand) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(commands) { command in
                Button {
                    onPick(command)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                        Text(command.prefix)
                            .font(DS.Typography.mono.weight(.semibold))
                            .foregroundStyle(DS.Palette.accent)
                            .frame(width: 72, alignment: .leading)
                        Text(command.summary)
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Palette.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Space.sm + 2)
                    .padding(.vertical, DS.Space.xs + 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if command != commands.last {
                    Divider().overlay(DS.Palette.separator)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Palette.border, lineWidth: 0.5)
        )
        .dsShadow(DS.Shadow.subtle())
    }
}

// MARK: - Auto-refreshing relative timestamp

/// Render a date as a relative timestamp, refreshing once per minute via TimelineView. Inherits
/// font/foreground from the surrounding context so it slots straight into HStacks without extra
/// modifiers.
struct RelativeTimestamp: View {
    let date: Date

    var body: some View {
        TimelineView(.everyMinute) { context in
            // Recompute relative to the actual current time on each tick so "Xm ago" advances.
            Text(RelativeTimeFormatter(clock: FixedSystemClock(now: context.date)).string(from: date))
        }
    }
}

/// SystemClock-shaped adapter that returns whatever date you hand it. Used only inside the
/// auto-refresh timestamp; in production data and in tests we use the SystemClock / FixedClock
/// from the core package.
private struct FixedSystemClock: AIAgentHubCore.Clock {
    let now: Date
}

// MARK: - Sidebar section header

private struct SessionGroupHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(.caption2, design: .default).weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(DS.Palette.textTertiary)
            Spacer()
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.md)
        .padding(.bottom, DS.Space.xxs)
        .background(DS.Palette.surfaceRaised)
    }
}
