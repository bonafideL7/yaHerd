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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var nav = NavigationCoordinator()
    @StateObject private var tagColorLibrary: TagColorLibraryStore
    private let sharedModelContainer: ModelContainer
    private let dependencies: AppDependencies
    private let startupStorageError: String?
    private let appSettingsSynchronizer: AppSettingsSynchronizer

    init() {
        let schema = Self.makeSchema()
        let preferences = AppPreferences()
        let syncMode = preferences.syncMode
        let appSettingsSynchronizer = AppSettingsSynchronizer.shared
        
        do {
            let container = try ModelContainerFactory.makeContainer(
                schema: schema,
                syncMode: syncMode
            )
            
            AppLaunchDiagnostics.record(
                requestedSyncMode: syncMode,
                actualStorageMode: syncMode == .iCloud ? .iCloud : .localOnly,
                cloudKitOpened: syncMode == .iCloud
            )

            appSettingsSynchronizer.startIfNeeded(syncMode: syncMode)
            self.appSettingsSynchronizer = appSettingsSynchronizer
            self.sharedModelContainer = container
            self.dependencies = AppDependencies(context: container.mainContext)
            self._tagColorLibrary = StateObject(wrappedValue: TagColorLibraryStore(context: container.mainContext, syncMode: syncMode))
            self.startupStorageError = nil
        } catch {
            let primaryError = error

            if syncMode == .iCloud {
                preferences.syncMode = .localOnly

                do {
                    let localContainer = try ModelContainerFactory.makeContainer(
                        schema: schema,
                        syncMode: .localOnly
                    )

                    let startupMessage = """
                    iCloud Sync could not be enabled, so yaHerd returned to Local Only mode. Your local data is still on this device. Original error: \(primaryError.localizedDescription)
                    """

                    AppLaunchDiagnostics.record(
                        requestedSyncMode: syncMode,
                        actualStorageMode: .localOnly,
                        cloudKitOpened: false,
                        startupError: startupMessage
                    )

                    self.appSettingsSynchronizer = appSettingsSynchronizer
                    self.sharedModelContainer = localContainer
                    self.dependencies = AppDependencies(context: localContainer.mainContext)
                    self._tagColorLibrary = StateObject(wrappedValue: TagColorLibraryStore(context: localContainer.mainContext, syncMode: .localOnly))
                    self.startupStorageError = startupMessage
                    return
                } catch {
                    let localRecoveryError = error

                    do {
                        let fallbackContainer = try ModelContainerFactory.makeRecoveryContainer(
                            schema: schema
                        )

                        let startupMessage = """
                        Persistent storage could not be opened. yaHerd is running in recovery mode, and changes from this session will not be saved.

                        iCloud container error: \(primaryError.localizedDescription)
                        Local recovery error: \(localRecoveryError.localizedDescription)
                        """

                        AppLaunchDiagnostics.record(
                            requestedSyncMode: syncMode,
                            actualStorageMode: .recovery,
                            cloudKitOpened: false,
                            startupError: startupMessage
                        )

                        self.appSettingsSynchronizer = appSettingsSynchronizer
                        self.sharedModelContainer = fallbackContainer
                        self.dependencies = AppDependencies(context: fallbackContainer.mainContext)
                        self._tagColorLibrary = StateObject(wrappedValue: TagColorLibraryStore(context: fallbackContainer.mainContext, syncMode: .localOnly))
                        self.startupStorageError = startupMessage
                        return
                    } catch {
                        fatalError("""
                        Failed to create SwiftData containers.

                        iCloud container error:
                        \(primaryError)

                        Local recovery error:
                        \(localRecoveryError)

                        Fallback container error:
                        \(error)
                        """)
                    }
                }
            }
            
            do {
                let fallbackContainer = try ModelContainerFactory.makeRecoveryContainer(
                    schema: schema
                )
                
                let startupMessage = """
                Persistent storage could not be opened. yaHerd is running in recovery mode, and changes from this session will not be saved. Original error: \(primaryError.localizedDescription)
                """

                AppLaunchDiagnostics.record(
                    requestedSyncMode: syncMode,
                    actualStorageMode: .recovery,
                    cloudKitOpened: false,
                    startupError: startupMessage
                )

                self.appSettingsSynchronizer = appSettingsSynchronizer
                self.sharedModelContainer = fallbackContainer
                self.dependencies = AppDependencies(context: fallbackContainer.mainContext)
                self._tagColorLibrary = StateObject(wrappedValue: TagColorLibraryStore(context: fallbackContainer.mainContext, syncMode: .localOnly))
                self.startupStorageError = startupMessage
            } catch {
                fatalError("""
                Failed to create SwiftData containers.
                
                Primary container error:
                \(primaryError)
                
                Fallback container error:
                \(error)
                """)
            }
        }
    }
    var body: some Scene {
        WindowGroup {
            RootAppView(storageError: startupStorageError)
                .environmentObject(nav)
                .environmentObject(tagColorLibrary)
                .environmentObject(dependencies)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        appSettingsSynchronizer.refreshFromICloudIfStarted()
                        tagColorLibrary.refresh()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }

    static func makeSchema() -> Schema {
        Schema([
            Animal.self,
            AnimalTag.self,
            TagColorDefinition.self,
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
