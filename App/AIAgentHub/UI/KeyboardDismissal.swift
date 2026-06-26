import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum KeyboardDismissal {
    /// Resigns first responder on the active key window. Must run on the main actor:
    /// `UIApplication.shared` and `NSApp.keyWindow` are both main-actor isolated under
    /// Swift 6 strict concurrency, so the helper has to declare the same isolation.
    @MainActor
    static func dismiss() {
        #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        #elseif os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }
}
