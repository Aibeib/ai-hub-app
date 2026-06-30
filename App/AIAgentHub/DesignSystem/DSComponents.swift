import SwiftUI
import AIAgentHubCore

// MARK: - DSBadge

/// Small status badge — provider chips, "Default", "Disabled"
struct DSBadge: View {
    let text: String
    var tint: Color = DS.Palette.accent
    var filled: Bool = true

    var body: some View {
        Text(text)
            .dsChip(tint: tint, filled: filled)
            .accessibilityLabel(text)
    }
}

// MARK: - DSStatusDot

/// 8pt status dot with optional pulsing animation.
///
/// We deliberately animate `opacity` on a fixed-size ring rather than stroke width.
/// Animating stroke width changes the path geometry and triggers SwiftUI to re-layout
/// every frame; opacity animates on the layer alone and is free on the compositor.
struct DSStatusDot: View {
    enum Status {
        case live, idle, warn, offline

        var color: Color {
            switch self {
            case .live: DS.Palette.positive
            case .idle: DS.Palette.textTertiary
            case .warn: DS.Palette.warning
            case .offline: DS.Palette.danger
            }
        }
    }

    let status: Status
    var animated: Bool = false
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(status.color.opacity(0.4), lineWidth: animated ? 4 : 0)
                    .opacity(animated && pulse ? 0.0 : 1.0)
            )
            .onAppear {
                guard animated else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse.toggle()
                }
            }
    }
}

// MARK: - DSProviderGlyph

/// Provider monogram avatar — soft tinted square with first letter of provider name
struct DSProviderGlyph: View {
    let provider: ModelProvider
    var size: CGFloat = 36

    private var letter: String {
        String(provider.displayName.first ?? "?").uppercased()
    }

    private var tint: Color {
        DS.Palette.providerChip(provider.displayName)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(tint.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(tint.opacity(0.32), lineWidth: 0.5)
                )

            Text(letter)
                .font(.system(size: size * 0.42, weight: .semibold, design: .serif))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - DSEmptyState

/// Composed empty state — designed, not the stock `ContentUnavailableView`.
struct DSEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var action: (label: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: DS.Space.md) {
            ZStack {
                Circle()
                    .fill(DS.Palette.accentSoft)
                    .frame(width: 84, height: 84)
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(DS.Palette.accent)
            }
            .padding(.bottom, DS.Space.xs)

            Text(title)
                .font(DS.Typography.title)
                .foregroundStyle(DS.Palette.textPrimary)

            Text(message)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .lineSpacing(3)

            if let action {
                Button {
                    action.run()
                } label: {
                    Text(action.label)
                        .font(DS.Typography.bodyEmphasized)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Space.lg)
                        .padding(.vertical, DS.Space.sm)
                        .background(
                            Capsule(style: .continuous)
                                .fill(DS.Palette.accent)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, DS.Space.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Space.xl)
    }
}

// MARK: - DSSectionHeader

/// Editorial-style section header — small-caps tracking, accented underline strip.
struct DSSectionHeader: View {
    let title: String
    var trailing: AnyView?

    init(_ title: String, trailing: AnyView? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.system(.caption, design: .default).weight(.semibold))
                    .tracking(2.0)
                    .foregroundStyle(DS.Palette.textTertiary)
                Rectangle()
                    .fill(DS.Palette.accent)
                    .frame(width: 24, height: 2)
            }
            Spacer()
            if let trailing {
                trailing
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.lg)
        .padding(.bottom, DS.Space.sm)
    }
}

// MARK: - DSPrimaryButton

struct DSPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.8)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(DS.Typography.bodyEmphasized)
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .background(
                Capsule(style: .continuous)
                    .fill(DS.Palette.accent)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DSGhostButton

struct DSGhostButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(DS.Typography.callout.weight(.medium))
            .foregroundStyle(DS.Palette.textPrimary)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.xs)
            .background(
                Capsule(style: .continuous)
                    .stroke(DS.Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
