//
//  MainTabView.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import SwiftUI
import SwiftData
import LucideIcons

struct MainTabView: View {
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(\.modelContext) private var context
    
    @State private var herdCount: Int = 0
    @State private var pastureCount: Int = 0
    @State private var alertCount: Int = 0
    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180
    @AppStorage("enablePastureOverstockWarnings") private var enablePastureOverstockWarnings = true
    @AppStorage("pastureCapacity") private var pastureCapacity = 30

    var body: some View {
        TabView {
            
            // DASHBOARD TAB
            NavigationStack(path: $nav.globalPath) {
                DashboardView()
                    .navigationDestination(for: Animal.self) { animal in
                        AnimalDetailView(animal: animal)
                    }
                    .navigationDestination(for: Pasture.self) { pasture in
                        PastureDetailView(pasture: pasture)
                    }
                    .navigationDestination(for: DashboardRoute.self) { route in
                        switch route {
                        case .animalList(let kind):
                            DashboardAnimalListView(kind: kind)
                        case .pastureList:
                            DashboardPastureListView()
                        }
                    }
            }
            .tabItem {
                Label("Dashboard", systemImage: "speedometer")
            }
            .tabBadge(alertCount)
            
            
            // HERD TAB
            NavigationStack {
                AnimalListView()
            }
            .tabItem {
                Label {
                    Text("Herd")
                } icon: {
                    if let base = UIImage(lucideId: "beef") {
                        let icon = base.scaled(to: CGSize(width: 28, height: 28))
                        Image(uiImage: icon)
                            .renderingMode(.template)
                    }
                }
            }
            
            // PASTURES TAB
            NavigationStack {
                PastureListView()
            }
            .tabItem {
                Label("Pastures", systemImage: "leaf")
            }

            // WORK TAB
            NavigationStack {
                WorkingSessionsView()
            }
            .tabItem {
                Label("Work", systemImage: "wrench")
            }
            
            // SETTINGS TAB
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .task {
            SampleDataService.seedIfNeeded(context: context)
            refreshCounts()
        }
    }
    
    private func refreshCounts() {
        do {
            let animals = try context.fetch(FetchDescriptor<Animal>())
            let pastures = try context.fetch(FetchDescriptor<Pasture>())

            herdCount = animals.filter { $0.status == .alive }.count
            pastureCount = pastures.count

            // NEW — compute dashboard alerts
            let alerts = DashboardService.generateAlerts(
                animals: animals,
                pastures: pastures,
                pregCheckIntervalDays: pregCheckIntervalDays,
                treatmentIntervalDays: treatmentIntervalDays,
                enablePastureOverstockWarnings: enablePastureOverstockWarnings,
                pastureCapacity: pastureCapacity
            )

            alertCount = alerts.count

        } catch {
            herdCount = 0
            pastureCount = 0
            alertCount = 0
        }
    }

}
