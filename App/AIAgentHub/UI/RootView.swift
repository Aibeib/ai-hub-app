import SwiftUI
import AIAgentHubCore
#if canImport(UIKit)
import UIKit
#endif

struct RootView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(AppLanguagePreference.self) private var languagePref
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedRoute: AppRoute = .chat
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .doubleColumn

    var body: some View {
        let language = languagePref.current

        Group {
            // iPhone (compact width) → tab bar. iPad / Mac (regular width) → split view.
            if horizontalSizeClass == .compact {
                CompactRootView(selectedRoute: $selectedRoute, language: language)
            } else {
                RegularRootView(
                    selectedRoute: $selectedRoute,
                    sidebarVisibility: $sidebarVisibility,
                    language: language
                )
            }
        }
        .tint(DS.Palette.accent)
        .preferredColorScheme(nil)
        .environment(\.appLanguage, language)
        .onReceive(NotificationCenter.default.publisher(for: .openModelsTab)) { _ in
            withAnimation(DS.Motion.springSnappy) {
                selectedRoute = .models
            }
        }
        .alert(
            runtime.pendingAuthorization?.title ?? "Authorization required",
            isPresented: Binding(
                get: { runtime.pendingAuthorization != nil },
                set: { if !$0 { runtime.resolvePendingAuthorization(approved: false) } }
            )
        ) {
            Button(language[.actionCancel], role: .cancel) {
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

extension Notification.Name {
    /// Posted when something (e.g. the missing-API-key banner) wants the user to land on
    /// the Models tab without manually digging through the bottom bar.
    static let openModelsTab = Notification.Name("AI-Hub.openModelsTab")
}

// MARK: - Compact (iPhone)

private struct CompactRootView: View {
    @Binding var selectedRoute: AppRoute
    let language: AppLanguage

    @MainActor
    init(selectedRoute: Binding<AppRoute>, language: AppLanguage) {
        self._selectedRoute = selectedRoute
        self.language = language

        #if canImport(UIKit)
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor(DS.Palette.tabBarBackground)
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(DS.Palette.textTertiary)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(DS.Palette.textTertiary)
        ]
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(DS.Palette.accent)
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(DS.Palette.accent)
        ]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        #endif
    }

    var body: some View {
        TabView(selection: $selectedRoute) {
            ForEach(AppRoute.allCases) { route in
                NavigationStack {
                    DetailContainer(route: route)
                        .navigationTitle(route.title(in: language))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(DS.Palette.surface, for: .navigationBar)
                        .toolbarBackground(.visible, for: .navigationBar)
                }
                .tabItem {
                    Label(route.title(in: language), systemImage: route.systemImage)
                }
                .tag(route)
            }
        }
    }
}

// MARK: - Regular (iPad / Mac)

private struct RegularRootView: View {
    @Binding var selectedRoute: AppRoute
    @Binding var sidebarVisibility: NavigationSplitViewVisibility
    let language: AppLanguage

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView(selectedRoute: $selectedRoute, language: language)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            DetailContainer(route: selectedRoute)
        }
        .navigationSplitViewStyle(.balanced)
        .background(DS.Palette.surface.ignoresSafeArea())
    }
}

// MARK: - Sidebar (iPad / Mac only)

private struct SidebarView: View {
    @Environment(AppRuntime.self) private var runtime
    @Binding var selectedRoute: AppRoute
    let language: AppLanguage

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

                Text(language == .zh ? "本地优先的助手" : "Local-first assistant")
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
                        language: language,
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
                    DSStatusDot(status: .live, animated: false)
                    Text(language == .zh ? "本地处理中" : "Local processing")
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
    let language: AppLanguage
    let isSelected: Bool
    let badge: Int?

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: route.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.textSecondary)
                .frame(width: 22, alignment: .center)

            Text(route.title(in: language))
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

enum AppRoute: String, CaseIterable, Identifiable, Hashable {
    case chat
    case models
    case devices
    case privacy

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .chat: language[.tabChat]
        case .models: language[.tabModels]
        case .devices: language[.tabDevices]
        case .privacy: language[.tabPrivacy]
        }
    }

    var systemImage: String {
        switch self {
        // Keep the bottom bar in one visual family with stable SF Symbols available on
        // the iOS 18 simulator. `sparkles.square` rendered blank on the Models tab in
        // practice, so use a more reliable model/AI metaphor instead.
        case .chat: "bubble.left.fill"
        case .models: "square.stack.3d.up.fill"
        case .devices: "laptopcomputer.and.iphone"
        case .privacy: "lock.shield.fill"
        }
    }
}
