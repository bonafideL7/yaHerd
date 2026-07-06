//
//  yaHerdApp.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import CloudKit
import SwiftUI
import SwiftData

@main
struct yaHerdApp: App {
    @UIApplicationDelegateAdaptor(CloudKitShareAppDelegate.self) private var cloudKitShareAppDelegate
    @StateObject private var nav = NavigationCoordinator()

    private let bootstrapState: AppBootstrapState
    private let appSettingsSynchronizer: AppSettingsSynchronizer

    init() {
        let schema = Self.makeSchema()
        let preferences = AppPreferences()
        let appSettingsSynchronizer = AppSettingsSynchronizer.shared

        self.appSettingsSynchronizer = appSettingsSynchronizer
        self.bootstrapState = Self.bootstrap(
            schema: schema,
            preferences: preferences,
            appSettingsSynchronizer: appSettingsSynchronizer
        )
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrapState {
            case .ready(let runtime):
                RunningAppView(
                    runtime: runtime,
                    appSettingsSynchronizer: appSettingsSynchronizer
                )
                .environmentObject(nav)

            case .storageUnavailable(let message):
                StartupStorageFailureView(message: message)
            }
        }
    }

    private static func bootstrap(
        schema: Schema,
        preferences: AppPreferencesProviding,
        appSettingsSynchronizer: AppSettingsSynchronizer
    ) -> AppBootstrapState {
        let syncMode = preferences.syncMode

        do {
            let container = try ModelContainerFactory.makeContainer(
                schema: schema,
                syncMode: syncMode
            )
            try DefaultHerdBootstrapper.ensureDefaultHerd(in: container.mainContext)

            AppLaunchDiagnostics.record(
                requestedSyncMode: syncMode,
                actualStorageMode: syncMode == .iCloud ? .iCloud : .localOnly,
                cloudKitOpened: syncMode == .iCloud
            )

            appSettingsSynchronizer.startIfNeeded(syncMode: syncMode)

            return .ready(
                AppRuntime(
                    modelContainer: container,
                    dependencies: AppDependencies(
                        context: container.mainContext,
                        tagColorDuplicateResolutionPolicy: syncMode.tagColorDuplicateResolutionPolicy
                    ),
                    syncMode: syncMode,
                    storageError: nil
                )
            )
        } catch {
            let primaryError = error

            if syncMode == .iCloud {
                preferences.syncMode = .localOnly
                appSettingsSynchronizer.stop()

                do {
                    let localContainer = try ModelContainerFactory.makeContainer(
                        schema: schema,
                        syncMode: .localOnly
                    )
                    try DefaultHerdBootstrapper.ensureDefaultHerd(in: localContainer.mainContext)

                    let startupMessage = """
                    iCloud Sync could not be enabled, so yaHerd returned to Local Only mode. Your local data is still on this device. Original error: \(primaryError.localizedDescription)
                    """

                    AppLaunchDiagnostics.record(
                        requestedSyncMode: syncMode,
                        actualStorageMode: .localOnly,
                        cloudKitOpened: false,
                        startupError: startupMessage
                    )

                    return .ready(
                        AppRuntime(
                            modelContainer: localContainer,
                            dependencies: AppDependencies(
                                context: localContainer.mainContext,
                                tagColorDuplicateResolutionPolicy: SyncMode.localOnly.tagColorDuplicateResolutionPolicy
                            ),
                            syncMode: .localOnly,
                            storageError: startupMessage
                        )
                    )
                } catch {
                    let localRecoveryError = error

                    do {
                        let fallbackContainer = try ModelContainerFactory.makeRecoveryContainer(
                            schema: schema
                        )
                        try DefaultHerdBootstrapper.ensureDefaultHerd(in: fallbackContainer.mainContext)

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

                        return .ready(
                            AppRuntime(
                                modelContainer: fallbackContainer,
                                dependencies: AppDependencies(
                            context: fallbackContainer.mainContext,
                            tagColorDuplicateResolutionPolicy: SyncMode.localOnly.tagColorDuplicateResolutionPolicy
                        ),
                                syncMode: .localOnly,
                                storageError: startupMessage
                            )
                        )
                    } catch {
                        let startupMessage = """
                        Persistent storage could not be opened, and the in-memory recovery store could not be started. No data was loaded and changes are disabled.

                        iCloud container error: \(primaryError.localizedDescription)
                        Local recovery error: \(localRecoveryError.localizedDescription)
                        In-memory recovery error: \(error.localizedDescription)
                        """

                        AppLaunchDiagnostics.record(
                            requestedSyncMode: syncMode,
                            actualStorageMode: .unavailable,
                            cloudKitOpened: false,
                            startupError: startupMessage
                        )

                        return .storageUnavailable(startupMessage)
                    }
                }
            }

            appSettingsSynchronizer.stop()

            do {
                let fallbackContainer = try ModelContainerFactory.makeRecoveryContainer(
                    schema: schema
                )
                try DefaultHerdBootstrapper.ensureDefaultHerd(in: fallbackContainer.mainContext)

                let startupMessage = """
                Persistent storage could not be opened. yaHerd is running in recovery mode, and changes from this session will not be saved. Original error: \(primaryError.localizedDescription)
                """

                AppLaunchDiagnostics.record(
                    requestedSyncMode: syncMode,
                    actualStorageMode: .recovery,
                    cloudKitOpened: false,
                    startupError: startupMessage
                )

                return .ready(
                    AppRuntime(
                        modelContainer: fallbackContainer,
                        dependencies: AppDependencies(
                            context: fallbackContainer.mainContext,
                            tagColorDuplicateResolutionPolicy: SyncMode.localOnly.tagColorDuplicateResolutionPolicy
                        ),
                        syncMode: .localOnly,
                        storageError: startupMessage
                    )
                )
            } catch {
                let startupMessage = """
                Persistent storage could not be opened, and the in-memory recovery store could not be started. No data was loaded and changes are disabled.

                Primary container error: \(primaryError.localizedDescription)
                In-memory recovery error: \(error.localizedDescription)
                """

                AppLaunchDiagnostics.record(
                    requestedSyncMode: syncMode,
                    actualStorageMode: .unavailable,
                    cloudKitOpened: false,
                    startupError: startupMessage
                )

                return .storageUnavailable(startupMessage)
            }
        }
    }

    static func makeSchema() -> Schema {
        Schema([
            Herd.self,
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

private extension SyncMode {
    var tagColorDuplicateResolutionPolicy: TagColorDuplicateResolutionPolicy {
        self == .iCloud ? .newestNonDefaultWins : .stableSortOrderWins
    }
}

private enum AppBootstrapState {
    case ready(AppRuntime)
    case storageUnavailable(String)
}

private struct AppRuntime {
    let modelContainer: ModelContainer
    let dependencies: AppDependencies
    let syncMode: SyncMode
    let storageError: String?
}

private struct RunningAppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tagColorLibrary: TagColorLibraryStore
    @State private var cloudKitShareInvitationCoordinator = CloudKitShareInvitationCoordinator()
    @State private var herdSharingSyncCoordinator: HerdSharingSyncCoordinator
    @State private var showsPendingCloudKitShareInvitation = false

    private let runtime: AppRuntime
    private let appSettingsSynchronizer: AppSettingsSynchronizer

    init(runtime: AppRuntime, appSettingsSynchronizer: AppSettingsSynchronizer) {
        self.runtime = runtime
        self.appSettingsSynchronizer = appSettingsSynchronizer
        self._tagColorLibrary = StateObject(
            wrappedValue: TagColorLibraryStore(
                repository: runtime.dependencies.tagColorRepository
            )
        )
        let sharingSyncCoordinator = HerdSharingSyncCoordinator(
            herdRepository: runtime.dependencies.herdRepository,
            sharingRepository: runtime.dependencies.herdSharingRepository,
            storageMode: runtime.syncMode.herdStorageMode,
            writePolicy: runtime.dependencies.herdCollaborationWritePolicy
        )
        runtime.dependencies.herdSharingMutationSyncScheduler.attach(
            coordinator: sharingSyncCoordinator
        )
        runtime.dependencies.herdCollaborationWritePolicy.setAccessRefreshRequestHandler { [weak sharingSyncCoordinator] reason in
            Task { @MainActor in
                await sharingSyncCoordinator?.refreshSharingAccessNow(trigger: .writePolicyPreflight(reason))
            }
        }
        self._herdSharingSyncCoordinator = State(initialValue: sharingSyncCoordinator)
    }

    var body: some View {
        RootAppView(storageError: runtime.storageError)
            .environmentObject(tagColorLibrary)
            .environment(\.dashboardRecordReader, runtime.dependencies.dashboardRepository)
            .environment(\.fieldCheckOverviewReader, runtime.dependencies.fieldCheckRepository)
            .environment(\.workingProtocolTemplateReader, runtime.dependencies.workingRepository)
            .environment(\.syncDiagnosticsRepository, runtime.dependencies.syncDiagnosticsRepository)
            .environment(\.herdRepository, runtime.dependencies.herdRepository)
            .environment(\.herdSharingRepository, runtime.dependencies.herdSharingRepository)
            .environment(\.cloudKitShareInvitationCoordinator, cloudKitShareInvitationCoordinator)
            .environment(\.herdSharingSyncCoordinator, herdSharingSyncCoordinator)
            .environment(\.herdCollaborationWritePolicy, runtime.dependencies.herdCollaborationWritePolicy)
            .environment(\.animalListRepository, runtime.dependencies.animalRepository)
            .environment(\.animalEditorRepository, runtime.dependencies.animalRepository)
            .environment(\.animalDetailRepository, runtime.dependencies.animalRepository)
            .environment(\.animalTimelineReader, runtime.dependencies.animalRepository)
            .environment(\.animalParentOptionReader, runtime.dependencies.animalRepository)
            .environment(\.animalHealthRecordAdder, runtime.dependencies.animalRepository)
            .environment(\.animalPregnancyCheckAdder, runtime.dependencies.animalRepository)
            .environment(\.pastureListRepository, runtime.dependencies.pastureRepository)
            .environment(\.pastureCreateRepository, runtime.dependencies.pastureRepository)
            .environment(\.pastureDetailRepository, runtime.dependencies.pastureRepository)
            .environment(\.pastureGroupListRepository, runtime.dependencies.pastureRepository)
            .environment(\.pastureGroupDetailRepository, runtime.dependencies.pastureRepository)
            .environment(\.pastureGroupEditorRepository, runtime.dependencies.pastureRepository)
            .environment(\.pastureReferenceReader, runtime.dependencies.pastureRepository)
            .environment(\.animalPastureMover, runtime.dependencies.animalRepository)
            .environment(\.fieldCheckPastureArchiveWriter, runtime.dependencies.fieldCheckRepository)
            .environment(\.fieldCheckSessionSetupRepository, runtime.dependencies.fieldCheckRepository)
            .environment(\.fieldCheckSessionDetailRepository, runtime.dependencies.fieldCheckRepository)
            .environment(\.fieldCheckAnimalDetailRepository, runtime.dependencies.fieldCheckRepository)
            .environment(\.workingSessionsRepository, runtime.dependencies.workingRepository)
            .environment(\.workingSessionDetailRepository, runtime.dependencies.workingRepository)
            .environment(\.newWorkingSessionRepository, runtime.dependencies.workingRepository)
            .environment(\.workingCollectAnimalsRepository, runtime.dependencies.workingRepository)
            .environment(\.workingQueueRepository, runtime.dependencies.workingRepository)
            .environment(\.workingQueueItemEditingRepository, runtime.dependencies.workingRepository)
            .environment(\.workingChuteRepository, runtime.dependencies.workingRepository)
            .environment(\.workingFinishSessionRepository, runtime.dependencies.workingRepository)
            .environment(\.workingProtocolTemplatesRepository, runtime.dependencies.workingRepository)
            .environment(\.workingProtocolTemplateCreator, runtime.dependencies.workingRepository)
            .environment(\.workingProtocolTemplateEditorRepository, runtime.dependencies.workingRepository)
            .environment(\.workingAnimalSummaryReader, runtime.dependencies.animalRepository)
            .environment(\.pastureReferenceDataReader, runtime.dependencies.pastureRepository)
            .environment(\.sampleDataSeeder, runtime.dependencies.sampleDataSeeder)
            .modelContainer(runtime.modelContainer)
            .task {
                await herdSharingSyncCoordinator.refreshSharingAccessNow(trigger: .appLaunch)
                herdSharingSyncCoordinator.requestAutomaticSync(trigger: .appLaunch)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    appSettingsSynchronizer.refreshFromICloudIfStarted()
                    tagColorLibrary.refresh()
                    Task {
                        await herdSharingSyncCoordinator.refreshSharingAccessNow(trigger: .appForeground)
                        herdSharingSyncCoordinator.requestAutomaticSync(trigger: .appForeground)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .yaHerdCloudKitShareAccepted)) { notification in
                if let metadata = notification.userInfo?[CloudKitShareNotificationUserInfoKey.metadata] as? CKShare.Metadata {
                    cloudKitShareInvitationCoordinator.recordAcceptedShare(metadata: metadata)
                }
                Task {
                    await herdSharingSyncCoordinator.refreshSharingAccessNow(
                        trigger: .shareInvitationAccepted,
                        minimumInterval: 0
                    )
                }
                showsPendingCloudKitShareInvitation = true
            }
            .alert("Herd Share Invitation Received", isPresented: $showsPendingCloudKitShareInvitation) {
                Button("OK", role: .cancel) {}
            } message: {
                if let summary = cloudKitShareInvitationCoordinator.pendingSummary {
                    Text("yaHerd received a CloudKit share invitation from \(summary.displayOwnerName). Open Settings > Herd Collaboration to accept it into the Core Data sharing bridge.")
                } else {
                    Text("yaHerd received a CloudKit share invitation. Open Settings > Herd Collaboration to accept it into the Core Data sharing bridge.")
                }
            }
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

private struct StartupStorageFailureView: View {
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Storage Unavailable", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text("yaHerd could not open persistent storage or start an in-memory recovery store.")
            } actions: {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No data was loaded. Changes are disabled for this launch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.horizontal)
            }
            .navigationTitle("yaHerd")
        }
    }
}
