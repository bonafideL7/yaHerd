import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private enum MainTab: Hashable {
    case home
    case dashboard
    case animals
}

struct MainTabView: View {
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var dependencies: AppDependencies
    @AppStorage("isDashboardEnabled") private var isDashboardEnabled = false

    @State private var selectedTab: MainTab = .home
    @State private var isShowingManagement = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
                    .appManagementToolbar(isPresented: $isShowingManagement)
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(MainTab.home)

            if isDashboardEnabled {
                NavigationStack(path: $nav.globalPath) {
                    DashboardView()
                        .navigationDestination(for: DashboardRoute.self, destination: dashboardDestination)
                        .appManagementToolbar(isPresented: $isShowingManagement)
                }
                .tabItem {
                    Label("Dashboard", systemImage: "rectangle.3.group")
                }
                .tag(MainTab.dashboard)
            }

            NavigationStack {
                HerdView()
                    .appManagementToolbar(isPresented: $isShowingManagement)
            }
            .tabItem {
                Label {
                    Text("YaHerd")
                } icon: {
                    if let base = UIImage(named: "Cow") {
                        let icon = base.scaled(to: CGSize(width: 32, height: 32))
                        Image(uiImage: icon)
                            .renderingMode(.template)
                    }
                }
            }
            .tag(MainTab.animals)
        }
        .yaherdTabBarMinimizeBehavior()
        .sheet(isPresented: $isShowingManagement) {
            ManagementSheetView()
        }
        .onChange(of: isDashboardEnabled) { _, isEnabled in
            if !isEnabled && selectedTab == .dashboard {
                selectedTab = .home
            }
        }
    }

    @ViewBuilder
    private func dashboardDestination(for route: DashboardRoute) -> some View {
        switch route {
        case .animal(let id):
            AnimalDetailView(animalID: id)
        case .pasture(let id):
            PastureDetailView(pastureID: id)
        case .animalList(let kind):
            DashboardAnimalListView(kind: kind, repository: dependencies.dashboardRepository)
        case .pastureList:
            DashboardPastureListView(repository: dependencies.dashboardRepository)
        }
    }
}

private struct ManagementSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ManagementView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private extension View {
    func appManagementToolbar(isPresented: Binding<Bool>) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresented.wrappedValue = true
                } label: {
                    Label("Manage", systemImage: "slider.horizontal.3")
                }
                .accessibilityLabel("Manage")
            }
        }
    }

    @ViewBuilder
    func yaherdTabBarMinimizeBehavior() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
