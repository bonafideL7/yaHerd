//
//  yaHerdApp.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI
import SwiftData

@main
struct yaHerdApp: App {
    @StateObject private var nav = NavigationCoordinator()
    @StateObject private var tagColorLibrary = TagColorLibraryStore()
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(nav)
                .environmentObject(tagColorLibrary)
        }
                .modelContainer(for: [
                    Animal.self,
                    AnimalTag.self,
                    Pasture.self,
                    HealthRecord.self,
                    PregnancyCheck.self,
                    MovementRecord.self,
                    StatusRecord.self,
                    WorkingSession.self,
                    WorkingQueueItem.self,
                    WorkingTreatmentRecord.self,
                    WorkingProtocolTemplate.self
                ])
        
    }
}
