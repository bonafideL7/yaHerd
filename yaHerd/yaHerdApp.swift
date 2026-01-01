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
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(nav)
        }
                .modelContainer(for: [
                    Animal.self,
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
