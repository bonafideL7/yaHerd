import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MainTabView: View {
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var dependencies: AppDependencies
    @AppStorage("isDashboardEnabled") private var isDashboardEnabled = true

    var body: some View {
        TabView {
            if isDashboardEnabled {
                NavigationStack(path: $nav.globalPath) {
                    DashboardView()
                        .navigationDestination(for: DashboardRoute.self, destination: dashboardDestination)
                }
                .tabItem {
                    Label("Dashboard", systemImage: "rectangle.3.group")
                }
            }

            NavigationStack {
                AnimalListView()
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

            NavigationStack {
                PastureListView(repository: dependencies.pastureRepository)
            }
            .tabItem {
                Label("Pastures", systemImage: "leaf")
            }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
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
