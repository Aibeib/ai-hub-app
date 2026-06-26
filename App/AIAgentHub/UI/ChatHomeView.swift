import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
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
    @FocusState private var searchFocused: Bool

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
        .overlay(alignment: .leading) {
            if isShowingSessionList {
                SessionDrawerOverlay(
                    language: language,
                    content: {
                        sessionListPane(forSheet: true)
                    },
                    onDismiss: {
                        isShowingSessionList = false
                    }
                )
                .ignoresSafeArea()
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .toolbar(isShowingSessionList ? .hidden : .visible, for: .tabBar)
        .toolbar(isShowingSessionList ? .hidden : .visible, for: .navigationBar)
        .animation(DS.Motion.springSnappy, value: isShowingSessionList)
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

            // New conversation. Filled-accent circle + white glyph — same visual weight
            // as the primary send button so the user reads it as "primary action", not as
            // a subtle ornament. The previous accentSoft tint with a textPrimary glyph
            // looked washed out against the light surface.
            Button {
                let session = runtime.createSession(title: language[.chatNewConversation])
                selectedSessionId = session.id
                inputFocused = true
            } label: {
                ZStack {
                    Circle().fill(DS.Palette.accent)
                    Image(systemName: "plus.message.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.white)
                        .offset(y: 0.5)
                }
                .frame(width: 36, height: 36)
                .shadow(color: DS.Palette.accent.opacity(0.25), radius: 6, x: 0, y: 3)
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
                        ZStack {
                            Circle().fill(DS.Palette.accent)
                            Image(systemName: "plus.message.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(.white)
                                .offset(y: 0.5)
                        }
                        .frame(width: 32, height: 32)
                        .shadow(color: DS.Palette.accent.opacity(0.25), radius: 6, x: 0, y: 3)
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
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit {
                        searchFocused = false
                        KeyboardDismissal.dismiss()
                    }
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

            // In drawer mode the conversation list is list-only. New conversation lives
            // on the main chat surface, matching the reference layout.

            // Session list. Use ScrollView/LazyVStack instead of List: List still hosts
            // UIKit row gesture machinery that interferes with our custom swipe row. A
            // plain scroll stack gives deterministic hit testing for the red delete action.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
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
                        let previews = visibleSessions.reduce(into: [UUID: String]()) {
                            $0[$1.id] = messagePreview(for: $1)
                        }
                        ForEach(groups, id: \.bucket) { group in
                            SessionGroupHeader(title: group.bucket.title)
                                .padding(.top, DS.Space.md)

                            ForEach(group.sessions) { session in
                                SessionRow(
                                    session: session,
                                    isSelected: session.id == selectedSessionId,
                                    preview: previews[session.id] ?? language[.chatStartHint],
                                    language: language,
                                    showsDeleteButton: forSheet,
                                    onSelect: {
                                        withAnimation(DS.Motion.springSnappy) {
                                            selectedSessionId = session.id
                                            if forSheet {
                                                isShowingSessionList = false
                                            }
                                        }
                                    },
                                    onPin: { runtime.togglePin(session.id) },
                                    onDelete: { deleteSession(session.id) }
                                )
                                .equatable()
                            }
                        }
                    }
                }
                .padding(.bottom, DS.Space.lg)
            }
            .background(DS.Palette.surfaceRaised)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(DS.Palette.surfaceRaised)
    }

    private func messagePreview(for session: ChatSessionRecord) -> String {
        let messages = runtime.chatRepository.messages(for: session.id)
        return messages.last?.content ?? language[.chatStartHint]
    }

    private func deleteSession(_ id: UUID) {
        runtime.deleteSession(id)

        let remainingVisible = visibleSessions
        if remainingVisible.isEmpty {
            selectedSessionId = nil
            isShowingSessionList = false
            return
        }

        if selectedSessionId == id {
            selectedSessionId = remainingVisible.first?.id
        }
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
                    deleteSession(session.id)
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
        // Establish an @Observable dependency on `messageRevision`. The repository's
        // `messages(for:)` is a direct SwiftData fetch with no observation; without this
        // line SwiftUI never re-renders when the user sends, deletes, or edits a message.
        // Read first, then ignore — the compiler keeps the access live.
        let _ = runtime.messageRevision
        let messages = runtime.chatRepository.messages(for: session.id)
        return TranscriptScrollView(
            messages: messages,
            streamingText: streamingText,
            streamingIsActive: streamingIsActive,
            language: language,
            modelName: runtime.resolvedModelName(for: session.id)
                ?? runtime.modelManager.defaultModel()?.name,
            isCompact: isCompact,
            onDeleteMessage: { id in runtime.deleteMessage(id, in: session.id) },
            onBranch: { id in
                if let branched = runtime.branchSession(from: session.id, atMessage: id) {
                    selectedSessionId = branched.id
                }
            },
            onEdit: { messageId, originalContent in
                editingMessage = MessageEditTarget(
                    sessionId: session.id,
                    messageId: messageId,
                    originalContent: originalContent
                )
            },
            onToggleBookmark: { id in runtime.toggleBookmark(id, in: session.id) },
            onDismissKeyboard: {
                inputFocused = false
                KeyboardDismissal.dismiss()
            }
        )
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
                HStack(alignment: .center, spacing: DS.Space.xs) {
                    TextField(language[.chatInputPlaceholder], text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(DS.Typography.body)
                        .lineLimit(1...6)
                        .focused($inputFocused)
                        .submitLabel(.send)
                        .onSubmit { Task { await send(in: session) } }
                        // SwiftUI's TextField(axis: .vertical) treats Return as "insert newline"
                        // even with submitLabel(.send), and .onSubmit doesn't always fire on
                        // iOS 17.x. Detect a trailing newline and treat it as the send action
                        // — strip the newline from the draft before sending so the model
                        // never receives the spurious "\n" the user didn't mean to type.
                        .onChange(of: draft) { _, newValue in
                            guard newValue.hasSuffix("\n") else { return }
                            // If the buffer is *only* whitespace + newlines, just collapse it.
                            let stripped = String(newValue.dropLast())
                            draft = stripped
                            let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty, !isSending else { return }
                            Task { await send(in: session) }
                        }

                    if !draft.isEmpty {
                        Button {
                            draft = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DS.Palette.textTertiary)
                                .frame(width: 28, height: 28)
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
                    ZStack {
                        Circle().fill(sendButtonFill)
                        Image(systemName: isSending ? "stop.fill" : "paperplane.fill")
                            .font(.system(size: isSending ? 13 : 16, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: isSending ? 0 : -1, y: isSending ? 0 : 1)
                    }
                    .accessibilityLabel(isSending ? (language == .zh ? "停止" : "Stop") : (language == .zh ? "发送" : "Send"))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(canSend || isSending ? 0.22 : 0), lineWidth: 1)
                    )
                    .shadow(
                        color: (isSending ? DS.Palette.danger : DS.Palette.accent).opacity(canSend || isSending ? 0.28 : 0),
                        radius: 10,
                        x: 0,
                        y: 5
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

    private var sendButtonFill: some ShapeStyle {
        if isSending {
            return AnyShapeStyle(DS.Palette.danger)
        }
        if canSend {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [DS.Palette.accent, DS.Palette.accent.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(DS.Palette.textTertiary.opacity(0.55))
    }

    private func send(in session: ChatSessionRecord) async {
        guard canSend else { return }
        let raw = draft
        inputFocused = false
        KeyboardDismissal.dismiss()

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
                streamingBuffer: buffer,
                onUserMessagePersisted: {
                    runtime.messagesChanged()
                    runtime.refreshSessions()
                },
                preferredResponseLanguage: language.rawValue
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
                streamingBuffer: buffer,
                onUserMessagePersisted: {
                    runtime.messagesChanged()
                    runtime.refreshSessions()
                },
                preferredResponseLanguage: language.rawValue
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
                    streamingBuffer: buffer,
                    preferredResponseLanguage: language.rawValue
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
                streamingBuffer: buffer,
                preferredResponseLanguage: language.rawValue
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
                runtime.messagesChanged()
                runtime.refreshSessions()
            } catch is CancellationError {
                runtime.messagesChanged()
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

// MARK: - Full-screen session drawer

private struct SessionDrawerOverlay<Content: View>: View {
    let language: AppLanguage
    @ViewBuilder let content: () -> Content
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var drawerWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.82, 340)
    }

    private var drawerBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.045, green: 0.045, blue: 0.050)
            : DS.Palette.surface
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(colorScheme == .dark ? 0.42 : 0.24)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DS.Palette.textSecondary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(language[.actionDone], action: onDismiss)
                        .font(DS.Typography.callout.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.top, DS.Space.lg)
                .padding(.bottom, DS.Space.xs)

                content()
            }
            .frame(width: drawerWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(drawerBackground.ignoresSafeArea())
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 26,
                    topTrailingRadius: 26,
                    style: .continuous
                )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.42 : 0.18), radius: 28, x: 10, y: 0)
            .ignoresSafeArea(edges: [.top, .bottom, .leading])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .ignoresSafeArea()
        .transition(.move(edge: .leading).combined(with: .opacity))
    }
}

// MARK: - Transcript scroll view

/// Transcript renderer. Owns the streaming-aware scroll behaviour that, prior to this
/// refactor, lived inline in ChatHomeView.transcriptScroll(for:). Extracting it into a
/// dedicated view lets us:
///
///   • Use a stable "bottom sentinel" view that the scroll lock anchors to. We pin the
///     bottom edge to the sentinel — NOT to the streaming bubble — so a growing bubble
///     never "drags" the viewport.
///   • Treat user upward scrolling as a signal to *stop* auto-following. Once the user
///     scrolls up to re-read context, every mature chat app (iMessage, ChatGPT,
///     Claude.ai, DeepSeek web) stops tugging them back down. We do the same: a
///     `PreferenceKey`-based bottom-distance sensor flips an `isPinnedToBottom` flag, and
///     auto-scroll only runs while pinned.
///   • Snap-scroll without `withAnimation`. iMessage and ChatGPT both render streaming
///     by *appending* and snapping the scroll position — no spring, no `.linear`. The
///     previous implementation wrapped every per-token `scrollTo` in
///     `withAnimation(.linear 0.12)`, which made successive scrolls interrupt each other
///     and produced both the visible jitter and the "lands on a random offset" symptom.
private struct TranscriptScrollView: View {
    let messages: [ChatMessageDTO]
    let streamingText: String
    let streamingIsActive: Bool
    let language: AppLanguage
    let modelName: String?
    let isCompact: Bool
    let onDeleteMessage: (UUID) -> Void
    let onBranch: (UUID) -> Void
    let onEdit: (UUID, String) -> Void
    let onToggleBookmark: (UUID) -> Void
    let onDismissKeyboard: () -> Void

    /// Pixel slack below which we consider the user "at the bottom" — if the next
    /// streaming chunk would push the sentinel out of view by less than this, we still
    /// auto-scroll. 80pt covers the typical streamingBubble height growth between two
    /// typewriter ticks at 60 chars/sec.
    private static let bottomLockSlack: CGFloat = 80

    @State private var isPinnedToBottom: Bool = true
    /// Last known distance (in points) from the visible bottom edge to the sentinel.
    /// Updated by the scroll-position sensor; used by the lock to decide whether
    /// auto-scroll should still fire.
    @State private var distanceFromBottom: CGFloat = 0
    @State private var isUserDragging = false

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
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
                                    onDelete: { onDeleteMessage(message.id) },
                                    onBranch: { onBranch(message.id) },
                                    onEdit: message.role == .user
                                        ? { onEdit(message.id, message.content) }
                                        : nil,
                                    onToggleBookmark: { onToggleBookmark(message.id) }
                                )
                                .equatable()
                                .id(message.id)
                            }

                            if streamingIsActive {
                                StreamingBubble(
                                    text: streamingText,
                                    modelName: modelName,
                                    language: language
                                )
                                // Deliberately NOT used as a scroll target — the streaming
                                // bubble grows over time so anchoring to it produces the
                                // "scroll keeps chasing itself" symptom the user reported.
                            }
                        }

                        // Bottom sentinel. 1pt tall, invisible, but it's what the scroll
                        // lock targets so the viewport always settles at the same place
                        // regardless of how the streaming bubble grew.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomSentinelID)
                            .background(bottomSensor(viewportHeight: viewport.size.height))
                    }
                    .padding(.horizontal, isCompact ? DS.Space.md : DS.Space.xl)
                    .padding(.vertical, DS.Space.lg)
                }
                .coordinateSpace(name: Self.scrollCoordinateSpace)
                .background(DS.Palette.surface)
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { _ in
                            isUserDragging = true
                            isPinnedToBottom = false
                        }
                        .onEnded { _ in
                            isUserDragging = false
                        }
                )
                .onTapGesture {
                    onDismissKeyboard()
                }
                // Auto-scroll the FIRST time streaming starts (so the new user message is
                // pinned to the bottom). After that the per-token streamingText listener
                // handles incremental follow-along.
                .onChange(of: streamingIsActive) { _, active in
                    if active {
                        isPinnedToBottom = true
                        snapToBottom(proxy: proxy)
                    } else if isPinnedToBottom {
                        // The streaming bubble is removed and replaced by the persisted
                        // assistant message at the end of a generation. Let SwiftUI commit
                        // that layout swap first, then snap to the bottom sentinel. Without
                        // this deferred settle the scroll view can keep an offset that is
                        // now beyond the shorter content, showing blank space until the
                        // user touches the scroll view.
                        DispatchQueue.main.async {
                            proxy.scrollTo(Self.bottomSentinelID, anchor: .bottom)
                        }
                    }
                }
                // Follow each streaming token IFF the user hasn't scrolled away.
                // No `withAnimation` — pure snap, the way every commercial chat client does
                // it. Animating per-token both stutters (animations interrupt) and produces
                // the "scrolls to a random offset" symptom because the LazyVStack content
                // size is still settling when the animation fires.
                .onChange(of: streamingText) { _, _ in
                    guard streamingIsActive, isPinnedToBottom, !isUserDragging else { return }
                    proxy.scrollTo(Self.bottomSentinelID, anchor: .bottom)
                }
                // Newly-appended messages (user sends, tool result lands, assistant message
                // finalizes) — same rules: only auto-scroll if pinned.
                .onChange(of: messages.count) { _, _ in
                    if isPinnedToBottom {
                        proxy.scrollTo(Self.bottomSentinelID, anchor: .bottom)
                    }
                }
                .onAppear {
                    // Initial position: bottom. Otherwise re-entering a long session lands
                    // at the top, which is jarring.
                    snapToBottom(proxy: proxy)
                }
                .onPreferenceChange(BottomDistancePreferenceKey.self) { distance in
                    distanceFromBottom = distance
                    // Treat "within slack of the bottom" as still-pinned. During an active
                    // user drag we do NOT re-enable auto-follow, otherwise the stream fights
                    // the user's finger and keeps pulling the transcript down.
                    if !isUserDragging {
                        isPinnedToBottom = distance <= Self.bottomLockSlack
                    }
                }
            }
        }
    }

    /// Snap to bottom without animation. Used on first appear / streaming start.
    private func snapToBottom(proxy: ScrollViewProxy) {
        proxy.scrollTo(Self.bottomSentinelID, anchor: .bottom)
    }

    /// Geometry probe that publishes the sentinel's distance from the visible bottom edge
    /// via a PreferenceKey. IMPORTANT: both quantities are measured in the same named
    /// scroll coordinate space. The previous version subtracted a named-coordinate value
    /// from a global-coordinate value, which made `isPinnedToBottom` randomly flip and
    /// caused exactly the "scroll jumps to arbitrary positions" symptom.
    private func bottomSensor(viewportHeight: CGFloat) -> some View {
        GeometryReader { geometry in
            let sentinelBottom = geometry.frame(in: .named(Self.scrollCoordinateSpace)).maxY
            let distance = max(0, sentinelBottom - viewportHeight)
            Color.clear
                .preference(key: BottomDistancePreferenceKey.self, value: distance)
        }
    }

    private static let bottomSentinelID = "__transcript_bottom__"
    private static let scrollCoordinateSpace = "transcriptScroll"
}

private struct BottomDistancePreferenceKey: PreferenceKey {
    // PreferenceKey's `defaultValue` is a Swift 6 strict-concurrency landmine when it's
    // a stored `static var`. SwiftUI calls it from main thread but the protocol doesn't
    // mark it isolated, so the compiler complains. Computing it on each access sidesteps
    // the warning at zero runtime cost.
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // We only ever publish one value (from the sentinel), so take the latest.
        value = nextValue()
    }
}

// MARK: - Session row

private struct SessionRow: View, Equatable {
    let session: ChatSessionRecord
    let isSelected: Bool
    let preview: String
    let language: AppLanguage
    let showsDeleteButton: Bool
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
            && lhs.showsDeleteButton == rhs.showsDeleteButton
    }

    var body: some View {
        // Plain HStack + contentShape — NOT a Button. A `Button(action:)` inside a List
        // row intercepts the row's gesture in ways that broke our previous swipe-to-delete
        // (the button consumed the horizontal pan and the swipe never started). Tapping
        // anywhere on the row still selects via `.onTapGesture` below.
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

            if showsDeleteButton {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(DS.Palette.danger))
                    .contentShape(Circle())
                    .onTapGesture {
                        onDelete()
                    }
            }
        }
        .padding(.horizontal, DS.Space.sm + 2)
        .padding(.vertical, DS.Space.sm)
        .background(
            isSelected ? DS.Palette.accentSoft : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button(action: onPin) {
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

                AssistantSegmentStack(segments: segments, isStreaming: false, language: language)
            }
            Spacer(minLength: 32)
        }
    }
}

private struct StreamingBubble: View {
    let text: String
    var modelName: String? = nil
    let language: AppLanguage

    /// Parse on every body invocation — streamingText changes per token, so caching here
    /// buys nothing. Parser is cheap; the cost is in markdown rendering which we share
    /// with `AssistantBubble` so geometry stays stable when the message finalizes (the
    /// "bubble jumps a size" bug came from the streaming view using `Text(plain)` while
    /// the final view used `Text(AttributedString)` — different line metrics).
    private var segments: [MessageSegment] {
        MessageSegmentParser.parse(text)
    }

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

                if segments.isEmpty {
                    // Placeholder before the model emits its first token. Sized the same as
                    // a one-line text bubble so the geometry doesn't pop when content
                    // arrives.
                    Text("…")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textTertiary)
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
                } else {
                    AssistantSegmentStack(segments: segments, isStreaming: true, language: language)
                }
            }
            Spacer(minLength: 32)
        }
        // Belt-and-braces: the StreamingBubble lives inside a transcript whose
        // ScrollViewReader fires `withAnimation(.linear)` on every streamingText change.
        // That implicit transaction makes the bubble animate its size as content grows
        // — visible as a per-token "pulse". Suppressing it here means tokens just
        // *appear*, the way every mature chat client (DeepSeek, ChatGPT, Claude) renders
        // streaming.
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

/// Renders an assistant message body (markdown + code + thinking) in a single styled
/// bubble. Used by both `AssistantBubble` (final message) and `StreamingBubble` (live
/// stream) so the layout, padding, font metrics and bubble background are guaranteed
/// identical — the previous mismatch was what produced the visible "size jump" the user
/// saw when a stream finalized.
private struct AssistantSegmentStack: View {
    let segments: [MessageSegment]
    let isStreaming: Bool
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case let .inline(content):
                    InlineMarkdownText(content: content)
                case let .code(lang, body):
                    CodeBlockView(language: lang, code: body)
                case let .thinking(content):
                    ThinkingBlockView(content: content, isStreaming: isStreaming, language: language)
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
                .stroke(isStreaming ? DS.Palette.accent.opacity(0.35) : DS.Palette.border, lineWidth: isStreaming ? 1 : 0.5)
        )
    }
}

/// DeepSeek-style collapsible "Thinking" card. Stays expanded by default — even after the
/// stream finishes — so the user can re-read the reasoning. They can collapse manually
/// via the chevron. We deliberately do NOT auto-collapse on completion: the previous
/// behaviour (where the block disappeared the moment streaming ended) made it impossible
/// to verify what the model thought after the fact.
///
/// Animation is suppressed on streaming token updates so the card doesn't pulse/jump as
/// each delta arrives — the visible "jitter" the user complained about came from the
/// implicit animation context leaking in from the ScrollViewReader's `withAnimation`
/// scrollTo call.
private struct ThinkingBlockView: View {
    let content: String
    let isStreaming: Bool
    let language: AppLanguage
    @State private var isExpanded: Bool = true

    init(content: String, isStreaming: Bool, language: AppLanguage) {
        self.content = content
        self.isStreaming = isStreaming
        self.language = language
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                // User-initiated expand/collapse — explicit easeOut so the toggle still
                // feels alive. Token-driven re-renders, in contrast, run with their
                // animation cleared by the `.transaction` modifier below.
                withAnimation(.easeOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "brain")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                    Text(headerLabel)
                        .font(DS.Typography.captionSmall.weight(.semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                    if isStreaming {
                        DSStatusDot(status: .live, animated: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, DS.Space.sm + 2)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(content)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.sm + 2)
                    .padding(.vertical, DS.Space.xs + 2)
                    .background(DS.Palette.surface.opacity(0.4))
                    // Streaming token updates carry SwiftUI's implicit animation context
                    // through from the ScrollViewReader's `withAnimation` block, which
                    // made the card visibly pulse / resize on every token. Clearing the
                    // animation here pins height growth to a single tick: text grows but
                    // doesn't bounce. The user's manual chevron tap still animates
                    // because that path uses its own explicit `withAnimation`.
                    .transaction { transaction in
                        if isStreaming {
                            transaction.animation = nil
                        }
                    }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(DS.Palette.surfaceElevated.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(DS.Palette.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        // Container-level suppression mirrors the inner text — bubble bounding box
        // shouldn't animate as tokens grow it.
        .transaction { transaction in
            if isStreaming {
                transaction.animation = nil
            }
        }
    }

    private var headerLabel: String {
        if isStreaming {
            return language == .zh ? "思考中..." : "Thinking..."
        }
        return language == .zh ? "推理过程" : "Reasoning"
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
    @FocusState private var editorFocused: Bool

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
                    .focused($editorFocused)
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
            .background(
                DS.Palette.surface
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editorFocused = false
                        KeyboardDismissal.dismiss()
                    }
            )
            .navigationTitle(language[.actionEditMessage])
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language[.actionCancel]) {
                        editorFocused = false
                        KeyboardDismissal.dismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language == .zh ? "保存并重新生成" : "Save & regenerate") {
                        editorFocused = false
                        KeyboardDismissal.dismiss()
                        onSave(content)
                        dismiss()
                    }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// MARK: - System prompt editor

private struct SystemPromptEditorView: View {
    let initial: String
    let language: AppLanguage
    let onSave: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @FocusState private var editorFocused: Bool

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
                        .focused($editorFocused)
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
            .background(
                DS.Palette.surface
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editorFocused = false
                        KeyboardDismissal.dismiss()
                    }
            )
            .navigationTitle(language[.actionSetSystemPrompt])
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language[.actionCancel]) {
                        editorFocused = false
                        KeyboardDismissal.dismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(language[.actionClear], role: .destructive) {
                        editorFocused = false
                        KeyboardDismissal.dismiss()
                        onSave(nil)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language[.actionSave]) {
                        editorFocused = false
                        KeyboardDismissal.dismiss()
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
