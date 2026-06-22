import SwiftUI
import AIAgentHubCore

@main
struct AIAgentHubMacApp: App {
    @State private var runtime = MacCompanionRuntime()

    var body: some Scene {
        WindowGroup {
            MacCompanionRootView()
                .environment(runtime)
        }
    }
}

