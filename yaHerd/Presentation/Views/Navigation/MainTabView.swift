import CoreData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MainTabView: View {
    @Environment(AppNavigationState.self) private var navigation
    @Environment(ApplicationSettings.self) private var applicationSettings
    @Environment(\.homeFeatureDependencies) private var homeDependencies
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

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
        .yaherdTabViewBottomAccessory(isVisible: showsHerdAccessory) {
            HerdTabBottomAccessory()
        }
        .appNavigationPresentations()
        .sharingAccessRefreshesForNavigation()
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            guard applicationSettings.syncMode == .iCloud else { return }

            // SwiftData's CloudKit import updates the persistent store asynchronously. The app's
            // snapshot-based screens do not automatically rerun their repository queries when that
            // happens, so bridge the Core Data remote-change notification into the existing app-wide
            // mutation stream. Every feature then reloads through its normal invalidation path.
            tagColorLibrary.refresh()
            (homeDependencies.mutationStream as? ApplicationMutationCenter)?.recordSharedStoreImport()
        }
        .onChange(of: applicationSettings.isDashboardEnabled) { _, isEnabled in
            if !isEnabled && navigation.selectedTab == .dashboard {
                navigation.selectedTab = .home
            }
        }
    }

    private var showsHerdAccessory: Bool {
        (navigation.selectedTab == .herd || navigation.selectedTab == .search)
            && navigation.herdRouter.mode == .animals
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
