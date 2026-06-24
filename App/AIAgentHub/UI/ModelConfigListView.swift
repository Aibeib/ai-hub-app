import SwiftUI
import AIAgentHubCore

/// Wrapper for sheet presentation. Either `.adding(nil)` for a new draft (defaultProvider lets
/// us pre-select e.g. DeepSeek when tapping "Add DeepSeek" later) or `.editing(record)` for an
/// existing one. Using `sheet(item:)` keyed on this enum guarantees the editor state is always
/// initialised from the right model record — `sheet(isPresented:)` could capture a stale snapshot.
enum ModelEditorTarget: Identifiable {
    case adding(ModelProvider?)
    case editing(ModelConfigRecord)

    var id: String {
        switch self {
        case .adding(let provider): return "add-\(provider?.rawValue ?? "any")"
        case .editing(let record): return "edit-\(record.id.uuidString)"
        }
    }
}

struct ModelConfigListView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.appLanguage) private var language
    @State private var editorTarget: ModelEditorTarget?
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
                    Text(language[.modelsTitle])
                        .font(DS.Typography.display)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(language[.modelsSubtitle])
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineSpacing(3)
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.lg)

                DSSectionHeader(
                    language[.modelsSectionActive],
                    trailing: AnyView(
                        Button {
                            editorTarget = .adding(nil)
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
                        title: language[.modelsEmptyTitle],
                        message: language[.modelsEmptySubtitle],
                        action: (language[.modelsEmptyCTA], {
                            editorTarget = .adding(nil)
                        })
                    )
                    .padding(.horizontal, DS.Space.xl)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DS.Space.lg)], spacing: DS.Space.lg) {
                        ForEach(enabledModels) { config in
                            ModelCard(
                                config: config,
                                isDefault: config.isDefault,
                                hasAPIKey: runtime.modelHasAPIKey(config.id),
                                language: language,
                                onEdit: {
                                    editorTarget = .editing(config)
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
                    DSSectionHeader(language[.modelsSectionInactive])

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: DS.Space.lg)], spacing: DS.Space.lg) {
                        ForEach(disabledModels) { config in
                            ModelCard(
                                config: config,
                                isDefault: false,
                                hasAPIKey: runtime.modelHasAPIKey(config.id),
                                language: language,
                                onEdit: {
                                    editorTarget = .editing(config)
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
                DSSectionHeader(language[.modelsSectionOnDevice])

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
                            Text(AppleFoundationAvailability.isAvailable
                                 ? language[.modelsAppleAvailable]
                                 : language[.modelsAppleRequires])
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
                        Text(language[.modelsKeychainNotice])
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
        .sheet(item: $editorTarget) { target in
            ModelConfigEditorView(target: target, language: language) { draft in
                do {
                    try runtime.saveModel(draft)
                    editorTarget = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert(language == .zh ? "保存失败" : "Model configuration failed", isPresented: Binding(
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
    let hasAPIKey: Bool
    let language: AppLanguage
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
                        DSBadge(text: language[.modelsLabelDefault], tint: DS.Palette.accent)
                    }
                    if !config.isEnabled {
                        DSBadge(text: language[.modelsLabelDisabled], tint: DS.Palette.textTertiary)
                    }
                    if config.provider != .apple {
                        if hasAPIKey {
                            DSBadge(text: language == .zh ? "已配置" : "Configured", tint: DS.Palette.positive)
                        } else {
                            DSBadge(text: language == .zh ? "缺密钥" : "Needs key", tint: DS.Palette.warning)
                        }
                    }
                }
            }

            Text(config.modelName)
                .font(DS.Typography.monoSmall)
                .foregroundStyle(DS.Palette.textTertiary)

            HStack(spacing: DS.Space.lg) {
                LabeledBadge(label: language[.modelsLabelTemp], value: String(format: "%.1f", config.temperature))
                LabeledBadge(label: language[.modelsLabelTokens], value: "\(config.maxTokens)")
            }

            Divider().overlay(DS.Palette.separator)

            HStack(spacing: DS.Space.sm) {
                Button(action: onEdit) {
                    Label(language == .zh ? "编辑" : "Edit", systemImage: "pencil")
                        .font(DS.Typography.caption.weight(.medium))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Label(language[.actionDelete], systemImage: "trash")
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

// MARK: - Editor (with model variant picker)

private struct ModelConfigEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var provider: ModelProvider
    @State private var selectedVariant: String   // canonical model id, or "__custom__"
    @State private var customModelName: String
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var revealAPIKey: Bool = false
    @State private var temperature: Double
    @State private var maxTokens: Int
    @State private var isDefault: Bool
    @State private var isEnabled: Bool

    private let id: UUID?
    private let hasExistingKey: Bool
    private let language: AppLanguage
    private let onSave: (ModelConfigurationDraft) -> Void

    private static let customSentinel = "__custom__"

    init(target: ModelEditorTarget, language: AppLanguage, onSave: @escaping (ModelConfigurationDraft) -> Void) {
        self.language = language
        self.onSave = onSave

        let initName: String
        let initProvider: ModelProvider
        let initModelName: String
        let initBaseURL: String
        let initTemperature: Double
        let initMaxTokens: Int
        let initIsDefault: Bool
        let initIsEnabled: Bool

        switch target {
        case let .editing(record):
            self.id = record.id
            self.hasExistingKey = false
            initName = record.name
            initProvider = record.provider
            initModelName = record.modelName
            initBaseURL = record.baseURL?.absoluteString ?? ""
            initTemperature = record.temperature
            initMaxTokens = record.maxTokens
            initIsDefault = record.isDefault
            initIsEnabled = record.isEnabled
        case let .adding(presetProvider):
            self.id = nil
            self.hasExistingKey = false
            let prov = presetProvider ?? .openai
            initName = prov.displayName
            initProvider = prov
            initModelName = ModelVariantCatalog.defaultVariantId(for: prov)
            initBaseURL = ""
            initTemperature = 0.7
            initMaxTokens = 4_096
            initIsDefault = false
            initIsEnabled = true
        }

        let matchesBuiltIn = ModelVariantCatalog.matchesBuiltIn(provider: initProvider, modelName: initModelName)
        let initVariant: String
        let initCustomName: String
        if matchesBuiltIn {
            initVariant = initModelName
            initCustomName = ""
        } else if initModelName.isEmpty {
            initVariant = ModelVariantCatalog.defaultVariantId(for: initProvider)
            initCustomName = ""
        } else {
            initVariant = Self.customSentinel
            initCustomName = initModelName
        }

        _name = State(initialValue: initName)
        _provider = State(initialValue: initProvider)
        _selectedVariant = State(initialValue: initVariant)
        _customModelName = State(initialValue: initCustomName)
        _baseURL = State(initialValue: initBaseURL)
        _apiKey = State(initialValue: "")
        _temperature = State(initialValue: initTemperature)
        _maxTokens = State(initialValue: initMaxTokens)
        _isDefault = State(initialValue: initIsDefault)
        _isEnabled = State(initialValue: initIsEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(language[.modelsSectionProvider]) {
                    TextField(language[.modelsFieldDisplayName], text: $name)

                    Picker(language[.modelsFieldProvider], selection: $provider) {
                        ForEach(ModelProvider.allCases.filter { $0 != .apple }, id: \.self) { p in
                            Label(p.displayName, systemImage: providerIcon(for: p))
                                .tag(p)
                        }
                    }
                    .onChange(of: provider) { _, newProvider in
                        // Reset variant selection to the new provider's default.
                        selectedVariant = ModelVariantCatalog.defaultVariantId(for: newProvider)
                        customModelName = ""
                        // Auto-update the display name when the user hasn't given it a custom one.
                        // We only overwrite when the current name still looks like an earlier provider's
                        // default — otherwise we respect what the user typed.
                        let allDefaults = ModelProvider.allCases.map(\.displayName)
                        if allDefaults.contains(name) || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            name = newProvider.displayName
                        }
                    }

                    Picker(language[.modelsFieldModelNamePicker], selection: $selectedVariant) {
                        ForEach(ModelVariantCatalog.variants(for: provider)) { variant in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(variant.displayName)
                                Text(variant.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(variant.id)
                        }
                        Text(language[.modelsFieldCustomModel]).tag(Self.customSentinel)
                    }
                    .pickerStyle(.menu)

                    if selectedVariant == Self.customSentinel {
                        TextField(language[.modelsFieldModelName], text: $customModelName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Text(volcengineHintIfNeeded() ?? language[.modelsFieldCustomModelHint])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if provider == .volcengine {
                        Text(language == .zh
                             ? "若你在火山方舟控制台创建了「在线推理接入点」(Endpoint ID 形如 ep-xxxxxx)，请选「自定义模型名」并粘贴。"
                             : "If you created an inference endpoint in the Volcengine Ark console, pick \"Custom\" and paste the endpoint id (looks like ep-xxxxxx).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    TextField(language[.modelsFieldCustomEndpoint], text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Text(defaultEndpointHint())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Section(language[.modelsSectionSecret]) {
                    HStack {
                        Group {
                            if revealAPIKey {
                                TextField(apiKeyPlaceholder, text: $apiKey)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField(apiKeyPlaceholder, text: $apiKey)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }
                        Button {
                            revealAPIKey.toggle()
                        } label: {
                            Image(systemName: revealAPIKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(language[.modelsFieldKeychainNotice])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(language[.modelsSectionParameters]) {
                    LabeledContent(language[.modelsFieldTemperature]) {
                        Text(temperature, format: .number.precision(.fractionLength(1)))
                    }
                    Slider(value: $temperature, in: 0...2, step: 0.1)
                    Stepper("\(language[.modelsFieldMaxTokens]): \(maxTokens)", value: $maxTokens, in: 1...200_000, step: 256)
                    Toggle(language[.modelsFieldIsDefault], isOn: $isDefault)
                    Toggle(language[.modelsFieldIsEnabled], isOn: $isEnabled)
                }
            }
            .navigationTitle(id == nil ? language[.modelsAddTitle] : language[.modelsEditTitle])
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language[.actionCancel]) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language[.actionSave]) {
                        let finalModelName = selectedVariant == Self.customSentinel
                            ? customModelName.trimmingCharacters(in: .whitespacesAndNewlines)
                            : selectedVariant
                        onSave(
                            ModelConfigurationDraft(
                                id: id,
                                name: name,
                                provider: provider,
                                modelName: finalModelName,
                                baseURL: baseURL.isEmpty ? nil : URL(string: baseURL),
                                apiKey: apiKey.isEmpty ? nil : apiKey,
                                temperature: temperature,
                                maxTokens: maxTokens,
                                isDefault: isDefault,
                                isEnabled: isEnabled
                            )
                        )
                    }
                    .disabled(saveDisabled)
                }
            }
        }
    }

    private var apiKeyPlaceholder: String {
        if id == nil {
            return language[.modelsFieldAPIKey]
        }
        return language[.modelsFieldAPIKeyReplace]
    }

    private var saveDisabled: Bool {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if selectedVariant == Self.customSentinel {
            return customModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    private func defaultEndpointHint() -> String {
        guard let url = provider.defaultBaseURL else {
            return language == .zh ? "本机模型，无需 endpoint。" : "On-device model, no endpoint required."
        }
        let prefix = language == .zh ? "留空使用默认：" : "Leave blank to use default: "
        return prefix + url.absoluteString
    }

    /// Show a clarifying hint for Volcengine when in custom-model mode — they need an `ep-xxx` id,
    /// not a model name like `gpt-4o`.
    private func volcengineHintIfNeeded() -> String? {
        guard provider == .volcengine, selectedVariant == Self.customSentinel else { return nil }
        return language == .zh
            ? "火山方舟的「model」字段应填接入点 ID，例如 ep-20250203120000-xxxxx。"
            : "Volcengine Ark expects an endpoint id (e.g. ep-20250203120000-xxxxx) as the model field."
    }

    private func providerIcon(for provider: ModelProvider) -> String {
        switch provider {
        case .openai: "circle.grid.3x3"
        case .deepseek: "circle.hexagonpath"
        case .anthropic: "sparkle"
        case .volcengine: "flame.fill"
        case .apple: "apple.logo"
        }
    }
}