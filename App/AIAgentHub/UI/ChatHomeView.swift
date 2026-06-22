import SwiftUI
import AIAgentHubCore

struct ChatHomeView: View {
    @State private var repository = InMemoryChatRepository()
    @State private var selectedSessionId: UUID?
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private let model = ResolvedModelConfig(
        id: UUID(),
        provider: .openai,
        name: "Demo OpenAI",
        modelName: "gpt-4.1-mini",
        endpoint: URL(string: "https://api.openai.com/v1/chat/completions"),
        apiKey: nil,
        temperature: 0.7,
        maxTokens: 2_048
    )

    var body: some View {
        VStack(spacing: 0) {
            if let selectedSessionId {
                ChatTranscriptView(messages: repository.messages(for: selectedSessionId))
            } else {
                ContentUnavailableView(
                    "No chat selected",
                    systemImage: "bubble.left",
                    description: Text("Create a session to start a local-first assistant conversation.")
                )
            }

            Divider()

            HStack(spacing: 12) {
                TextField("Ask AI Agent Hub...", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding()
        }
        .navigationTitle("Chat")
        .toolbar {
            Button {
                let session = repository.createSession(title: "New Chat", modelConfigId: nil)
                selectedSessionId = session.id
            } label: {
                Label("New Chat", systemImage: "plus")
            }
        }
        .alert("Message failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func send() async {
        guard let selectedSessionId else {
            let session = repository.createSession(title: "New Chat", modelConfigId: nil)
            self.selectedSessionId = session.id
            await send()
            return
        }

        let message = draft
        draft = ""
        isSending = true
        defer { isSending = false }

        do {
            let orchestrator = ChatOrchestrator(
                repository: repository,
                aiService: StubAIService(events: [.token("Demo response. Configure an API key to call a real model."), .completed]),
                redactor: PrivacyRedactor(),
                contextBuilder: ContextBuilder()
            )
            try await orchestrator.sendUserMessage(message, in: selectedSessionId, using: model)
        } catch {
            draft = message
            errorMessage = error.localizedDescription
        }
    }
}

private struct ChatTranscriptView: View {
    let messages: [ChatMessageDTO]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.role.rawValue.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(message.content)
                            .padding(12)
                            .background(message.role == .user ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                }
            }
            .padding()
        }
    }
}

