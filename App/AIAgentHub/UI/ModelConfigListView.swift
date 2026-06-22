import SwiftUI
import AIAgentHubCore

struct ModelConfigListView: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var isShowingEditor = false
    @State private var editingConfig: ModelConfigRecord?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Third-party models") {
                ForEach(runtime.modelConfigs) { config in
                    Button {
                        editingConfig = config
                        isShowingEditor = true
                    } label: {
                        ModelConfigRow(config: config)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets {
                        let config = runtime.modelConfigs[index]
                        do {
                            try runtime.deleteModel(config.id)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
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
                editingConfig = nil
                isShowingEditor = true
            } label: {
                Label("Add Model", systemImage: "plus")
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            ModelConfigEditorView(config: editingConfig) { draft in
                do {
                    try runtime.saveModel(draft)
                    isShowingEditor = false
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("Model configuration failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

private struct ModelConfigRow: View {
    let config: ModelConfigRecord

    var body: some View {
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
                if !config.isEnabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("\(config.provider.displayName) · \(config.modelName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ModelConfigEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var provider: ModelProvider
    @State private var modelName: String
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var temperature: Double
    @State private var maxTokens: Int
    @State private var isDefault: Bool
    @State private var isEnabled: Bool

    private let id: UUID?
    private let onSave: (ModelConfigurationDraft) -> Void

    init(config: ModelConfigRecord?, onSave: @escaping (ModelConfigurationDraft) -> Void) {
        id = config?.id
        _name = State(initialValue: config?.name ?? "")
        _provider = State(initialValue: config?.provider ?? .openai)
        _modelName = State(initialValue: config?.modelName ?? "")
        _baseURL = State(initialValue: config?.baseURL?.absoluteString ?? "")
        _apiKey = State(initialValue: "")
        _temperature = State(initialValue: config?.temperature ?? 0.7)
        _maxTokens = State(initialValue: config?.maxTokens ?? 2_048)
        _isDefault = State(initialValue: config?.isDefault ?? false)
        _isEnabled = State(initialValue: config?.isEnabled ?? true)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    TextField("Display name", text: $name)
                    Picker("Provider", selection: $provider) {
                        ForEach(ModelProvider.allCases.filter { $0 != .apple }, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    TextField("Model name", text: $modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Custom endpoint (optional)", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Secret") {
                    SecureField(id == nil ? "API key" : "New API key (leave blank to keep)", text: $apiKey)
                    Text("Keys are saved through the Keychain-backed secret store.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Parameters") {
                    LabeledContent("Temperature") {
                        Text(temperature, format: .number.precision(.fractionLength(1)))
                    }
                    Slider(value: $temperature, in: 0...2, step: 0.1)
                    Stepper("Max tokens: \(maxTokens)", value: $maxTokens, in: 1...200_000, step: 256)
                    Toggle("Default model", isOn: $isDefault)
                    Toggle("Enabled", isOn: $isEnabled)
                }
            }
            .navigationTitle(id == nil ? "Add Model" : "Edit Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            ModelConfigurationDraft(
                                id: id,
                                name: name,
                                provider: provider,
                                modelName: modelName,
                                baseURL: baseURL.isEmpty ? nil : URL(string: baseURL),
                                apiKey: apiKey.isEmpty ? nil : apiKey,
                                temperature: temperature,
                                maxTokens: maxTokens,
                                isDefault: isDefault,
                                isEnabled: isEnabled
                            )
                        )
                    }
                }
            }
        }
    }
}
