import SwiftUI
import SwiftData
import AIAgentHubCore

@main
struct AIAgentHubApp: App {
    private let container: ModelContainer
    @State private var runtime = AppRuntime()

    init() {
        do {
            container = try ModelContainer(
                for: StoredModelConfig.self,
                StoredChatSession.self,
                StoredChatMessage.self,
                StoredToolExecutionLog.self,
                StoredBoundDevice.self
            )
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(runtime)
        }
        .modelContainer(container)
    }
}
