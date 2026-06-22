import SwiftUI
import AIAgentHubCore

struct ModelConfigListView: View {
    @State private var configs: [ModelConfigRecord] = [
        ModelConfigRecord(
            name: "OpenAI",
            provider: .openai,
            modelName: "gpt-4.1-mini",
            isDefault: true
        ),
        ModelConfigRecord(
            name: "DeepSeek",
            provider: .deepseek,
            modelName: "deepseek-chat"
        ),
        ModelConfigRecord(
            name: "Claude",
            provider: .anthropic,
            modelName: "claude-sonnet-4-5"
        )
    ]

    var body: some View {
        List {
            Section("Third-party models") {
                ForEach(configs) { config in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(config.name)
                                .font(.headline)
                            if config.isDefault {
                                Text("Default")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.blue.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                        Text("\(config.provider.displayName) · \(config.modelName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("On-device AI") {
                HStack {
                    Label("Apple Foundation Models", systemImage: "apple.logo")
                    Spacer()
                    Text(AppleFoundationAvailability.isAvailable ? "Available" : "Requires iOS 26+")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Security") {
                Text("API keys are stored in Keychain by the platform adapter. They are never stored in SwiftData model rows.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Models")
        .toolbar {
            Button {
                configs.append(
                    ModelConfigRecord(
                        name: "Custom Model",
                        provider: .openai,
                        modelName: "custom-model"
                    )
                )
            } label: {
                Label("Add Model", systemImage: "plus")
            }
        }
    }
}

