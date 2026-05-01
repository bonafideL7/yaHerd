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
    private let sharedModelContainer: ModelContainer
    private let dependencies: AppDependencies

    init() {
        let schema = Schema([
            Animal.self,
            AnimalTag.self,
            AnimalStatusReference.self,
            Pasture.self,
            PastureGroup.self,
            HealthRecord.self,
            PregnancyCheck.self,
            MovementRecord.self,
            StatusRecord.self,
            WorkingSession.self,
            WorkingQueueItem.self,
            WorkingTreatmentRecord.self,
            WorkingProtocolTemplate.self,
            FieldCheckSession.self,
            FieldCheckAnimalCheck.self,
            FieldCheckFinding.self
        ])

        do {
            // This app is still pre-release. Use a new persistent store for the
            // required distinguishing-feature order schema instead of attempting
            // to migrate old local development data that omitted `order`.
            let configuration = ModelConfiguration("yaHerdRequiredOrderStore", schema: schema)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.sharedModelContainer = container
            self.dependencies = AppDependencies(context: container.mainContext)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(nav)
                .environmentObject(tagColorLibrary)
                .environmentObject(dependencies)
        }
        .modelContainer(sharedModelContainer)
    }
}
