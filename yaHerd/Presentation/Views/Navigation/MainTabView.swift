import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import SwiftData

struct MainTabView: View {
    @EnvironmentObject private var nav: NavigationCoordinator
    @Environment(\.modelContext) private var context

    var body: some View {
        TabView {
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
                PastureListView()
            }
            .tabItem {
                Label("Pastures", systemImage: "leaf")
            }
        }
        .task {
//            SampleDataService.seedDefaultsIfNeeded(context: context)
//            SampleLargeDataService.seedIfNeeded(context: context)            
        }
    }
}
