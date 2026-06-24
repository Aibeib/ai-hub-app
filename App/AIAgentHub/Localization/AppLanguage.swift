import Foundation
import Observation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case zh
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zh: "简体中文"
        case .en: "English"
        }
    }

    var shortLabel: String {
        switch self {
        case .zh: "中"
        case .en: "EN"
        }
    }
}

/// Application-wide language preference. Persisted in UserDefaults so it survives launches.
/// Default is `.zh` for new installs; existing installs without the key also fall back to
/// `.zh` per product requirement.
@Observable
@MainActor
final class AppLanguagePreference {
    private static let storageKey = "AI-Hub.AppLanguage"

    var current: AppLanguage {
        didSet {
            guard current != oldValue else { return }
            UserDefaults.standard.set(current.rawValue, forKey: Self.storageKey)
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.storageKey),
           let stored = AppLanguage(rawValue: raw) {
            current = stored
        } else {
            current = .zh
        }
    }
}

/// Convenience for SwiftUI views that don't already hold a reference to the preference.
private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .zh
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}
