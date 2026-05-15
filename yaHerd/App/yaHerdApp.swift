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
    private let startupStorageError: String?

    init() {
        let schema = Self.makeSchema()

        do {
            // This app is still pre-release. Use a new persistent store for the
            // required distinguishing-feature order schema instead of attempting
            // to migrate old local development data that omitted `order`.
            let configuration = ModelConfiguration("yaHerdRequiredOrderStore", schema: schema)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.sharedModelContainer = container
            self.dependencies = AppDependencies(context: container.mainContext)
            self.startupStorageError = nil
        } catch {
            do {
                let fallbackConfiguration = ModelConfiguration("yaHerdRecoveryStore", schema: schema, isStoredInMemoryOnly: true)
                let fallbackContainer = try ModelContainer(for: schema, configurations: [fallbackConfiguration])
                self.sharedModelContainer = fallbackContainer
                self.dependencies = AppDependencies(context: fallbackContainer.mainContext)
                self.startupStorageError = "Persistent storage could not be opened. yaHerd is running in recovery mode, and changes from this session will not be saved. Original error: \(error.localizedDescription)"
            } catch {
                preconditionFailure("Failed to create fallback model container: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootAppView(storageError: startupStorageError)
                .environmentObject(nav)
                .environmentObject(tagColorLibrary)
                .environmentObject(dependencies)
        }
        .modelContainer(sharedModelContainer)
    }

    static func makeSchema() -> Schema {
        Schema([
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
    }
}


private struct RootAppView: View {
    let storageError: String?
    @State private var showsStorageError: Bool

    init(storageError: String?) {
        self.storageError = storageError
        self._showsStorageError = State(initialValue: storageError != nil)
    }

    var body: some View {
        MainTabView()
            .alert("Storage Recovery Mode", isPresented: $showsStorageError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storageError ?? "Persistent storage could not be opened.")
            }
    }
}
