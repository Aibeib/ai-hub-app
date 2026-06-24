import SwiftUI

/// Design tokens for AI Agent Hub.
///
/// Direction: "Quiet luxury, violet ink" — paired with the brand mark (gradient indigo→violet).
/// Light mode is a clean, slightly cool off-white anchored by a saturated violet accent. Dark
/// mode is a deep indigo-black, the same family as the icon's gradient base. Both feel like the
/// same product, not two inverted skins.
public enum DS {}

// MARK: - Palette

public extension DS {
    /// Adaptive palette. Each entry has explicit light/dark values so neither mode looks like a
    /// machine-inverted copy of the other.
    enum Palette {
        /// Page background — slightly cool off-white in light, deep indigo-black in dark
        public static let surface = Color(
            light: Color(red: 0.973, green: 0.969, blue: 0.984),
            dark: Color(red: 0.055, green: 0.051, blue: 0.110)
        )

        /// Raised cards and side rails — slightly elevated from `surface`
        public static let surfaceRaised = Color(
            light: Color(red: 0.988, green: 0.984, blue: 0.996),
            dark: Color(red: 0.086, green: 0.082, blue: 0.157)
        )

        /// Most-elevated layer — bubbles, inputs, model cards
        public static let surfaceElevated = Color(
            light: Color(red: 1.0, green: 1.0, blue: 1.0),
            dark: Color(red: 0.122, green: 0.118, blue: 0.196)
        )

        /// Primary ink (headlines, body text)
        public static let textPrimary = Color(
            light: Color(red: 0.094, green: 0.082, blue: 0.149),
            dark: Color(red: 0.957, green: 0.957, blue: 0.973)
        )

        /// Secondary copy, captions, metadata
        public static let textSecondary = Color(
            light: Color(red: 0.345, green: 0.333, blue: 0.412),
            dark: Color(red: 0.682, green: 0.690, blue: 0.745)
        )

        /// Quiet copy, placeholders, dividers
        public static let textTertiary = Color(
            light: Color(red: 0.541, green: 0.529, blue: 0.604),
            dark: Color(red: 0.443, green: 0.451, blue: 0.522)
        )

        /// Hero accent — saturated violet matching the icon's mid-band
        public static let accent = Color(
            light: Color(red: 0.467, green: 0.298, blue: 0.929),
            dark: Color(red: 0.659, green: 0.522, blue: 1.000)
        )

        /// Soft tint of accent — for active-state backgrounds, badges
        public static let accentSoft = Color(
            light: Color(red: 0.937, green: 0.910, blue: 0.996),
            dark: Color(red: 0.184, green: 0.149, blue: 0.298)
        )

        /// Hairlines, separator strokes
        public static let separator = Color(
            light: Color(red: 0.898, green: 0.886, blue: 0.929),
            dark: Color(red: 0.192, green: 0.184, blue: 0.275)
        )

        /// Subtle border on surfaces
        public static let border = Color(
            light: Color(red: 0.906, green: 0.894, blue: 0.937),
            dark: Color(red: 0.231, green: 0.220, blue: 0.318)
        )

        // Semantic — tuned so they read against the indigo-black bg in dark mode
        public static let positive = Color(
            light: Color(red: 0.169, green: 0.467, blue: 0.341),
            dark: Color(red: 0.494, green: 0.804, blue: 0.620)
        )
        public static let warning = Color(
            light: Color(red: 0.741, green: 0.486, blue: 0.137),
            dark: Color(red: 0.973, green: 0.745, blue: 0.408)
        )
        public static let danger = Color(
            light: Color(red: 0.769, green: 0.227, blue: 0.337),
            dark: Color(red: 0.973, green: 0.486, blue: 0.580)
        )

        // Bubble specifics
        public static let userBubble = Color(
            light: Color(red: 0.467, green: 0.298, blue: 0.929),
            dark: Color(red: 0.553, green: 0.408, blue: 0.965)
        )
        public static let userBubbleText = Color(
            light: Color.white,
            dark: Color.white
        )
        public static let assistantBubble = Color(
            light: Color(red: 1.0, green: 1.0, blue: 1.0),
            dark: Color(red: 0.122, green: 0.118, blue: 0.196)
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
            case "volcengine", "火山方舟", "ark":
                Color(red: 0.929, green: 0.396, blue: 0.243)  // 火山橘红
            case "apple", "apple foundation models":
                Color(red: 0.392, green: 0.392, blue: 0.408)
            default:
                Color(red: 0.467, green: 0.298, blue: 0.929)
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
    /// No-op shadow on iOS — `shadow(radius:)` triggers an off-screen render pass per call.
    /// On scrollable views with dozens of `dsCard()` instances this is the dominant frame-
    /// drop source on real devices. We keep the API so call sites compile, but visually we
    /// fall back to the stroke + slight surface elevation built into `dsCard`. Re-enable
    /// per call site with `.shadow(...)` only when the card is truly hero-level.
    func dsShadow(_ style: DS.ShadowStyle) -> some View {
        // Keep the call cheap: just return self. We *don't* call `.shadow(...)` here.
        self
    }

    /// Card surface with subtle stroke — used everywhere instead of raw `.background`.
    /// No shadow: the visual lift comes from the stroke + a brighter fill against the
    /// page surface, which is GPU-free.
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
