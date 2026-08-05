import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MainTabView: View {
    @Environment(AppNavigationState.self) private var navigation
    @Environment(ApplicationSettings.self) private var applicationSettings

    var body: some View {
        @Bindable var navigation = navigation

        TabView(selection: $navigation.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeTabRootView()
            }

            if applicationSettings.isDashboardEnabled {
                Tab("Dashboard", systemImage: "rectangle.3.group", value: AppTab.dashboard) {
                    DashboardTabRootView()
                }
            }

            Tab(value: AppTab.herd) {
                HerdTabRootView(tab: .herd)
            } label: {
                Label {
                    Text("YaHerd")
                } icon: {
                    yaherdTabIcon
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                HerdTabRootView(tab: .search)
            }
        }
        .yaherdTabBarMinimizeBehavior()
        .yaherdTabViewBottomAccessory(isVisible: showsAnimalQueryAccessory) {
            HerdTabBottomAccessory()
        }
        .appNavigationPresentations()
        .sharingAccessRefreshesForNavigation()
        .onChange(of: applicationSettings.isDashboardEnabled) { _, isEnabled in
            if !isEnabled && navigation.selectedTab == .dashboard {
                navigation.selectedTab = .home
            }
        }
    }

    private var showsAnimalQueryAccessory: Bool {
        guard navigation.selectedTab == .herd || navigation.selectedTab == .search else {
            return false
        }

        guard let destination = navigation.herdRouter.path(for: navigation.selectedTab).last else {
            return true
        }

        if case .pasture = destination {
            return true
        }

        return false
    }

    @ViewBuilder
    private var yaherdTabIcon: some View {
#if canImport(UIKit)
        if let base = UIImage(named: "Cow") {
            let icon = base.scaled(to: CGSize(width: 32, height: 32))
            Image(uiImage: icon)
                .renderingMode(.template)
        } else {
            Image(systemName: "tag")
        }
#else
        Image(systemName: "tag")
#endif
    }
}

private extension View {
    func yaherdTabBarMinimizeBehavior() -> some View {
        tabBarMinimizeBehavior(.onScrollDown)
    }

    @ViewBuilder
    func yaherdTabViewBottomAccessory<Accessory: View>(
        isVisible: Bool,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        if isVisible {
            tabViewBottomAccessory {
                accessory()
            }
        } else {
            self
        }
    }
}
