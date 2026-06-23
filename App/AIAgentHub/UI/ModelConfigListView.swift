import SwiftUI
import AIAgentHubCore

struct ModelConfigListView: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var isShowingEditor = false
    @State private var editingConfig: ModelConfigRecord?
    @State private var errorMessage: String?

    private var enabledModels: [ModelConfigRecord] {
        runtime.modelConfigs.filter(\.isEnabled)
    }

    private var disabledModels: [ModelConfigRecord] {
        runtime.modelConfigs.filter { !$0.isEnabled }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                // Header
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Models")
                        .font(DS.Typography.display)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text("Choose which AI providers to use, and configure your API keys for each one.")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineSpacing(3)
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.lg)

                DSSectionHeader(
                    "Active The Third-Party Providers",
                    trailing: AnyView(
                        Button {
                            editingConfig = nil
                            isShowingEditor = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DS.Palette.accent)
                        }
                        .buttonStyle(.plain)
                    )
                )

                if enabledModels.isEmpty {
                    DSEmptyState(
                        icon: "cpu",
                        title: "No models configured",
                        message: "Add a provider like OpenAI, DeepSeek, or Claude to get started.",
                        action: ("Add model", {
                            editingConfig = nil
                            isShowingEditor = true
                        })
                    )
                    .padding(.horizontal, DS.Space.xl)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: DS.Space.lg)], spacing: DS.Space.lg) {
                        ForEach(enabledModels) { config in
                            ModelCard(
                                config: config,
                                isDefault: config.isDefault,
                                onEdit: {
                                    editingConfig = config
                                    isShowingEditor = true
                                },
                                onDelete: {
                                    do {
                                        try runtime.deleteModel(config.id)
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, DS.Space.xl)
                }

                if !disabledModels.isEmpty {
                    DSSectionHeader("Inactive")

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: DS.Space.lg)], spacing: DS.Space.lg) {
                        ForEach(disabledModels) { config in
                            ModelCard(
                                config: config,
                                isDefault: false,
                                onEdit: {
                                    editingConfig = config
                                    isShowingEditor = true
                                },
                                onDelete: {
                                    do {
                                        try runtime.deleteModel(config.id)
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, DS.Space.xl)
                }

                // On-device section
                DSSectionHeader("On-Device")

                GroupBox {
                    HStack(spacing: DS.Space.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DS.Palette.textTertiary.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(DS.Palette.textSecondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Foundation Models")
                                .font(DS.Typography.headline)
                                .foregroundStyle(DS.Palette.textPrimary)
                            Text(AppleFoundationAvailability.isAvailable ? "Available on this device" : "Requires iOS 26+")
                                .font(DS.Typography.caption)
                                .foregroundStyle(AppleFoundationAvailability.isAvailable ? DS.Palette.positive : DS.Palette.textTertiary)
                        }

                        Spacer()

                        DSStatusDot(status: AppleFoundationAvailability.isAvailable ? .live : .offline, animated: AppleFoundationAvailability.isAvailable)
                    }
                    .padding(DS.Space.md)
                }
                .groupBoxStyle(.dsCard)
                .padding(.horizontal, DS.Space.xl)

                // Security notice
                Section {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "key.horizontal")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.Palette.accent)
                        Text("API keys are stored in the system Keychain and are never persisted in plaintext.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }
                    .padding(DS.Space.md)
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.bottom, DS.Space.xxl)
            }
        }
        .background(DS.Palette.surface)
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

// MARK: - Model card

private struct ModelCard: View {
    let config: ModelConfigRecord
    let isDefault: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .top) {
                DSProviderGlyph(provider: config.provider)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                        .font(DS.Typography.headline)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(config.provider.displayName)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                    if isDefault {
                        DSBadge(text: "Default", tint: DS.Palette.accent)
                    }
                    if !config.isEnabled {
                        DSBadge(text: "Disabled", tint: DS.Palette.textTertiary)
                    }
                }
            }

            Text(config.modelName)
                .font(DS.Typography.monoSmall)
                .foregroundStyle(DS.Palette.textTertiary)

            HStack(spacing: DS.Space.lg) {
                LabeledBadge(label: "Temp", value: String(format: "%.1f", config.temperature))
                LabeledBadge(label: "Tokens", value: "\(config.maxTokens)")
            }

            Divider().overlay(DS.Palette.separator)

            HStack(spacing: DS.Space.sm) {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(DS.Typography.caption.weight(.medium))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(DS.Typography.caption.weight(.medium))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Space.md)
        .dsCard()
    }
}

private struct LabeledBadge: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(DS.Typography.captionSmall)
                .foregroundStyle(DS.Palette.textTertiary)
            Text(value)
                .font(DS.Typography.monoSmall)
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }
}

// MARK: - GroupBox custom style

extension GroupBoxStyle where Self == DSCardGroupBoxStyle {
    static var dsCard: DSCardGroupBoxStyle { DSCardGroupBoxStyle() }
}

struct DSCardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .padding(.bottom, DS.Space.xs)
            configuration.content
        }
        .padding(DS.Space.md)
        .dsCard()
    }
}

// MARK: - Editor (reused from original, lightly styled)

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
                            Label(provider.displayName, systemImage: providerIcon(for: provider))
                                .tag(provider)
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

    private func providerIcon(for provider: ModelProvider) -> String {
        switch provider {
        case .openai: "circle.grid.3x3"
        case .deepseek: "circle.hexagonpath"
        case .anthropic: "sparkle"
        case .apple: "apple.logo"
        }
    }
}