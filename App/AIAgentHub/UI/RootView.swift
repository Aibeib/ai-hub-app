import SwiftUI
import AIAgentHubCore

struct RootView: View {
    @Environment(AppRuntime.self) private var runtime
    @State private var selectedRoute: AppRoute = .chat
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView(selectedRoute: $selectedRoute)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            DetailContainer(route: selectedRoute)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(DS.Palette.accent)
        .preferredColorScheme(nil)
        .background(DS.Palette.surface.ignoresSafeArea())
        .alert(
            runtime.pendingAuthorization?.title ?? "Authorization required",
            isPresented: Binding(
                get: { runtime.pendingAuthorization != nil },
                set: { if !$0 { runtime.resolvePendingAuthorization(approved: false) } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                runtime.resolvePendingAuthorization(approved: false)
            }
            Button("Approve", role: .destructive) {
                runtime.resolvePendingAuthorization(approved: true)
            }
        } message: {
            Text(runtime.pendingAuthorization?.message ?? "")
        }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @Environment(AppRuntime.self) private var runtime
    @Binding var selectedRoute: AppRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand header
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.xs) {
                    ZStack {
                        Circle()
                            .fill(DS.Palette.accent)
                            .frame(width: 28, height: 28)
                        Text("A")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(.white)
                    }

                    Text("AI Hub")
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Palette.textPrimary)
                }

                Text("Local-first assistant")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .tracking(0.4)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.top, DS.Space.lg)
            .padding(.bottom, DS.Space.lg)

            // Routes
            VStack(spacing: 2) {
                ForEach(AppRoute.allCases) { route in
                    SidebarRouteRow(
                        route: route,
                        isSelected: route == selectedRoute,
                        badge: badge(for: route)
                    )
                    .onTapGesture {
                        withAnimation(DS.Motion.springSnappy) {
                            selectedRoute = route
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Space.xs)

            Spacer()

            // Footer: status
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Divider()
                    .overlay(DS.Palette.separator)

                HStack(spacing: DS.Space.xs) {
                    DSStatusDot(status: .live, animated: true)
                    Text("Local processing")
                        .font(DS.Typography.captionSmall)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.Palette.surfaceRaised.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func badge(for route: AppRoute) -> Int? {
        switch route {
        case .chat:
            let count = runtime.sessions.filter { !$0.isArchived }.count
            return count > 0 ? count : nil
        case .models:
            let count = runtime.modelConfigs.filter(\.isEnabled).count
            return count > 0 ? count : nil
        default:
            return nil
        }
    }
}

private struct SidebarRouteRow: View {
    let route: AppRoute
    let isSelected: Bool
    let badge: Int?

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: route.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.textSecondary)
                .frame(width: 22, alignment: .center)

            Text(route.title)
                .font(DS.Typography.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? DS.Palette.textPrimary : DS.Palette.textSecondary)

            Spacer()

            if let badge {
                Text("\(badge)")
                    .font(DS.Typography.captionSmall.monospacedDigit())
                    .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.textTertiary)
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(isSelected ? DS.Palette.accentSoft : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Detail container

private struct DetailContainer: View {
    let route: AppRoute

    var body: some View {
        Group {
            switch route {
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
        .background(DS.Palette.surface.ignoresSafeArea())
    }
}

// MARK: - Route enum

enum AppRoute: String, CaseIterable, Identifiable {
    case chat
    case models
    case devices
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: "Conversations"
        case .models: "Models"
        case .devices: "Devices"
        case .privacy: "Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right"
        case .models: "cpu"
        case .devices: "iphone.and.arrow.forward"
        case .privacy: "lock.shield"
        }
    }
}
