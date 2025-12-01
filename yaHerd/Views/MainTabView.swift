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
    @Environment(\.modelContext) private var context
    
    @State private var herdCount: Int = 0
    @State private var pastureCount: Int = 0
    @State private var alertCount: Int = 0
    
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
            .tabBadge(herdCount)
            
            
            // PASTURES TAB
            NavigationStack {
                PastureListView()
            }
            .tabItem {
                Label("Pastures", systemImage: "leaf")
            }
            .tabBadge(pastureCount)
            
            
            // SETTINGS TAB
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .task {
            refreshCounts()
        }
    }
    
    private func refreshCounts() {
        do {
            let animals = try context.fetch(FetchDescriptor<Animal>())
            let pastures = try context.fetch(FetchDescriptor<Pasture>())
            
            herdCount = animals.filter { $0.status == .alive }.count
            pastureCount = pastures.count
            alertCount = 0
            
        } catch {
            herdCount = 0
            pastureCount = 0
            alertCount = 0
        }
    }
}
