import SwiftUI

/// Design tokens for AI Agent Hub.
///
/// Direction: "Quiet editorial" — warm off-white in light mode, deep ink in dark mode, with a
/// single warm clay accent. Generous whitespace, refined typography, soft layered depth. The
/// goal is for the app to feel calm and considered rather than another templated AI chat UI.
public enum DS {}

// MARK: - Palette

public extension DS {
    /// Adaptive palette. Each entry has explicit light/dark values so neither mode looks like a
    /// machine-inverted copy of the other.
    enum Palette {
        /// Page background — warm off-white / deep ink
        public static let surface = Color(
            light: Color(red: 0.984, green: 0.973, blue: 0.957),
            dark: Color(red: 0.063, green: 0.075, blue: 0.090)
        )

        /// Raised cards and side rails — slightly elevated from `surface`
        public static let surfaceRaised = Color(
            light: Color(red: 1.0, green: 0.996, blue: 0.984),
            dark: Color(red: 0.094, green: 0.110, blue: 0.133)
        )

        /// Most-elevated layer — bubbles, inputs, model cards
        public static let surfaceElevated = Color(
            light: Color(red: 1.0, green: 1.0, blue: 1.0),
            dark: Color(red: 0.133, green: 0.149, blue: 0.176)
        )

        /// Primary ink (headlines, body text)
        public static let textPrimary = Color(
            light: Color(red: 0.078, green: 0.078, blue: 0.094),
            dark: Color(red: 0.961, green: 0.953, blue: 0.937)
        )

        /// Secondary copy, captions, metadata
        public static let textSecondary = Color(
            light: Color(red: 0.337, green: 0.337, blue: 0.353),
            dark: Color(red: 0.659, green: 0.667, blue: 0.690)
        )

        /// Quiet copy, placeholders, dividers
        public static let textTertiary = Color(
            light: Color(red: 0.553, green: 0.541, blue: 0.525),
            dark: Color(red: 0.420, green: 0.435, blue: 0.467)
        )

        /// Hero accent — warm clay. Used sparingly, never decoratively.
        public static let accent = Color(
            light: Color(red: 0.722, green: 0.275, blue: 0.169),
            dark: Color(red: 0.937, green: 0.612, blue: 0.380)
        )

        /// Soft tint of accent — for active-state backgrounds, badges
        public static let accentSoft = Color(
            light: Color(red: 0.984, green: 0.918, blue: 0.875),
            dark: Color(red: 0.235, green: 0.149, blue: 0.122)
        )

        /// Hairlines, separator strokes
        public static let separator = Color(
            light: Color(red: 0.910, green: 0.886, blue: 0.847),
            dark: Color(red: 0.184, green: 0.200, blue: 0.227)
        )

        /// Subtle border on surfaces
        public static let border = Color(
            light: Color(red: 0.918, green: 0.890, blue: 0.847),
            dark: Color(red: 0.227, green: 0.243, blue: 0.275)
        )

        // Semantic
        public static let positive = Color(
            light: Color(red: 0.169, green: 0.467, blue: 0.341),
            dark: Color(red: 0.451, green: 0.776, blue: 0.604)
        )
        public static let warning = Color(
            light: Color(red: 0.643, green: 0.408, blue: 0.118),
            dark: Color(red: 0.937, green: 0.706, blue: 0.388)
        )
        public static let danger = Color(
            light: Color(red: 0.690, green: 0.165, blue: 0.165),
            dark: Color(red: 0.945, green: 0.490, blue: 0.471)
        )

        // Bubble specifics
        public static let userBubble = Color(
            light: Color(red: 0.078, green: 0.078, blue: 0.094),
            dark: Color(red: 0.937, green: 0.612, blue: 0.380)
        )
        public static let userBubbleText = Color(
            light: Color(red: 0.984, green: 0.973, blue: 0.957),
            dark: Color(red: 0.063, green: 0.075, blue: 0.090)
        )
        public static let assistantBubble = Color(
            light: Color(red: 1.0, green: 1.0, blue: 1.0),
            dark: Color(red: 0.133, green: 0.149, blue: 0.176)
        )

        // Provider brand chips
        public static func providerChip(_ name: String) -> Color {
            switch name.lowercased() {
            case "openai":
                Color(red: 0.063, green: 0.553, blue: 0.443)
            case "deepseek":
                Color(red: 0.231, green: 0.412, blue: 0.851)
            case "anthropic", "claude":
                Color(red: 0.769, green: 0.467, blue: 0.247)
            case "apple", "apple foundation models":
                Color(red: 0.392, green: 0.392, blue: 0.408)
            default:
                Color(red: 0.435, green: 0.451, blue: 0.490)
            }
        }
    }
}

// MARK: - Spacing

public extension DS {
    enum Space {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
        public static let xxxl: CGFloat = 72
    }
}

// MARK: - Radius

public extension DS {
    enum Radius {
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 10
        public static let md: CGFloat = 14
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 28
        public static let pill: CGFloat = 999
    }
}

// MARK: - Typography

public extension DS {
    enum Typography {
        /// Display headings — serif (New York) for editorial feel, only used at large sizes
        public static let display = Font.system(.largeTitle, design: .serif).weight(.semibold)
        public static let title = Font.system(.title2, design: .serif).weight(.semibold)

        /// Section / nav titles
        public static let headline = Font.system(.headline, design: .default).weight(.semibold)
        public static let subheadline = Font.system(.subheadline, design: .default).weight(.medium)

        /// Body & UI
        public static let body = Font.system(.body, design: .default)
        public static let bodyEmphasized = Font.system(.body, design: .default).weight(.semibold)
        public static let callout = Font.system(.callout, design: .default)

        /// Caption and metadata — slightly rounded for friendliness
        public static let caption = Font.system(.caption, design: .rounded).weight(.medium)
        public static let captionSmall = Font.system(.caption2, design: .rounded).weight(.medium)

        /// Monospace for code blocks, ids, model names
        public static let mono = Font.system(.callout, design: .monospaced)
        public static let monoSmall = Font.system(.caption, design: .monospaced)
    }
}

// MARK: - Motion

public extension DS {
    enum Motion {
        public static let durationFast: Double = 0.18
        public static let durationNormal: Double = 0.28
        public static let durationSlow: Double = 0.45

        public static let easeOut = Animation.timingCurve(0.16, 1.0, 0.30, 1.0, duration: durationNormal)
        public static let easeOutFast = Animation.timingCurve(0.16, 1.0, 0.30, 1.0, duration: durationFast)
        public static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
        public static let springSnappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
    }
}

// MARK: - Shadow

public extension DS {
    enum Shadow {
        public static func soft(_ scheme: ColorScheme = .light) -> ShadowStyle {
            scheme == .dark
                ? ShadowStyle(color: .black.opacity(0.50), radius: 22, x: 0, y: 10)
                : ShadowStyle(color: .black.opacity(0.08), radius: 22, x: 0, y: 10)
        }

        public static func subtle(_ scheme: ColorScheme = .light) -> ShadowStyle {
            scheme == .dark
                ? ShadowStyle(color: .black.opacity(0.40), radius: 8, x: 0, y: 3)
                : ShadowStyle(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        }
    }

    struct ShadowStyle: Sendable {
        public let color: Color
        public let radius: CGFloat
        public let x: CGFloat
        public let y: CGFloat
    }
}

// MARK: - Light/Dark helper

extension Color {
    /// Build an adaptive color from explicit light/dark sources without dropping into UIKit.
    /// Falls back to the trait-collection bridge on iOS / NSAppearance on macOS so colours stay
    /// dynamic when the user toggles appearance mid-flight.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self = Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #else
        self = light
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - View modifiers

public extension View {
    func dsShadow(_ style: DS.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    /// Card surface with subtle stroke and depth — used everywhere instead of raw `.background`.
    func dsCard(_ corner: CGFloat = DS.Radius.lg) -> some View {
        modifier(DSCardModifier(corner: corner))
    }

    /// Pill chip background — for tags, badges, status indicators
    func dsChip(tint: Color = DS.Palette.accent, filled: Bool = true) -> some View {
        modifier(DSChipModifier(tint: tint, filled: filled))
    }
}

private struct DSCardModifier: ViewModifier {
    let corner: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(DS.Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(DS.Palette.border, lineWidth: 0.5)
            )
            .dsShadow(DS.Shadow.subtle(scheme))
    }
}

private struct DSChipModifier: ViewModifier {
    let tint: Color
    let filled: Bool

    func body(content: Content) -> some View {
        content
            .font(DS.Typography.captionSmall)
            .foregroundStyle(filled ? Color.white : tint)
            .padding(.horizontal, DS.Space.xs)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(filled ? tint : tint.opacity(0.14))
            )
    }
}
