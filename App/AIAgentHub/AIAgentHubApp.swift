import SwiftUI
import SwiftData
import AIAgentHubCore

@main
struct AIAgentHubApp: App {
    private let container: ModelContainer

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
        }
        .modelContainer(container)
    }
}

