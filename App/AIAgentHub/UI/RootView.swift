import SwiftUI
import AIAgentHubCore

struct RootView: View {
    @State private var selectedRoute = AppRoute.chat

    var body: some View {
        NavigationSplitView {
            List(AppRoute.allCases, selection: $selectedRoute) { route in
                Label(route.title, systemImage: route.systemImage)
                    .tag(route)
            }
            .navigationTitle("AI Agent Hub")
        } detail: {
            switch selectedRoute {
            case .chat:
                ChatHomeView()
            case .models:
                ModelConfigListView()
            case .devices:
                DeviceManagementView()
            case .privacy:
                PrivacyAndLogsView()
            }
        }
    }
}

enum AppRoute: String, CaseIterable, Identifiable {
    case chat
    case models
    case devices
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            "Chats"
        case .models:
            "Models"
        case .devices:
            "Devices"
        case .privacy:
            "Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .chat:
            "bubble.left.and.bubble.right"
        case .models:
            "cpu"
        case .devices:
            "iphone.and.arrow.forward"
        case .privacy:
            "lock.shield"
        }
    }
}

