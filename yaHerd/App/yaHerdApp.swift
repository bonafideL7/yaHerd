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
        let preferences = AppPreferences()
        let appSettingsSynchronizer = AppSettingsSynchronizer.shared

        self.appSettingsSynchronizer = appSettingsSynchronizer
        self.bootstrapState = Self.bootstrap(
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
        preferences: AppPreferencesProviding,
        appSettingsSynchronizer: AppSettingsSynchronizer
    ) -> AppBootstrapState {
        let syncMode = preferences.syncMode

        do {
            let container = try ModelContainerFactory.makeContainer(
                syncMode: syncMode
            )
            try Self.runStartupDataMigrations(in: container.mainContext, storageScope: syncMode.rawValue)

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
                    dataAccessMode: .readWrite,
                    recoveryContext: nil,
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
                        syncMode: .localOnly
                    )
                    try Self.runStartupDataMigrations(in: localContainer.mainContext, storageScope: SyncMode.localOnly.rawValue)

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
                            dataAccessMode: .readWrite,
                            recoveryContext: nil,
                            storageError: startupMessage
                        )
                    )
                } catch {
                    let localRecoveryError = error

                    do {
                        let fallbackContainer = try ModelContainerFactory.makeRecoveryContainer()

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
                                    tagColorDuplicateResolutionPolicy: SyncMode.localOnly.tagColorDuplicateResolutionPolicy,
                                    dataAccessMode: .recoveryReadOnly
                                ),
                                syncMode: .localOnly,
                                dataAccessMode: .recoveryReadOnly,
                                recoveryContext: RecoveryModeContext(
                                    requestedSyncMode: syncMode,
                                    startupError: startupMessage
                                ),
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
                let fallbackContainer = try ModelContainerFactory.makeRecoveryContainer()

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
                            tagColorDuplicateResolutionPolicy: SyncMode.localOnly.tagColorDuplicateResolutionPolicy,
                            dataAccessMode: .recoveryReadOnly
                        ),
                        syncMode: .localOnly,
                        dataAccessMode: .recoveryReadOnly,
                        recoveryContext: RecoveryModeContext(
                            requestedSyncMode: syncMode,
                            startupError: startupMessage
                        ),
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

    private static func runStartupDataMigrations(in context: ModelContext, storageScope: String) throws {
        try DefaultHerdBootstrapper.ensureDefaultHerdForAppLaunch(
            in: context,
            storageScope: storageScope
        )
        try FieldCheckHistoricalSnapshotMigrator.runIfNeeded(
            in: context,
            storageScope: storageScope
        )
    }

    static func makeSchema() -> Schema {
        ModelContainerFactory.schema
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
    let dataAccessMode: AppDataAccessMode
    let recoveryContext: RecoveryModeContext?
    let storageError: String?
}

private struct RunningAppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tagColorLibrary: TagColorLibraryStore
    @StateObject private var recoveryModeController: RecoveryModeController
    @State private var cloudKitShareInvitationCoordinator: CloudKitShareInvitationCoordinator
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
        self._cloudKitShareInvitationCoordinator = State(
            initialValue: CloudKitShareInvitationCoordinator(
                shareAdapter: runtime.dependencies.cloudKitShareAdapter
            )
        )
        self._recoveryModeController = StateObject(
            wrappedValue: RecoveryModeController(
                context: runtime.recoveryContext ?? RecoveryModeContext(
                    requestedSyncMode: runtime.syncMode,
                    startupError: "Recovery mode is not active."
                ),
                diagnosticsRepository: runtime.dependencies.syncDiagnosticsRepository,
                automaticallyRefreshDiagnostics: runtime.dataAccessMode.isRecoveryMode
            )
        )
        let sharingSyncCoordinator = HerdSharingSyncCoordinator(
            herdRepository: runtime.dependencies.herdRepository,
            sharingRepository: runtime.dependencies.herdSharingRepository,
            storageMode: runtime.syncMode.herdStorageMode,
            writePolicy: runtime.dependencies.herdCollaborationWritePolicy,
            conflictReviewStore: runtime.dependencies.herdSharingConflictReviewStore
        )
        if runtime.dataAccessMode.allowsDataMutations {
            runtime.dependencies.herdSharingMutationSyncScheduler.attach(
                coordinator: sharingSyncCoordinator
            )
            runtime.dependencies.herdCollaborationWritePolicy.setAccessRefreshRequestHandler { [weak sharingSyncCoordinator] reason in
                sharingSyncCoordinator?.requestSharingAccessRefreshForMutationPreflight(reason: reason)
            }
        }
        self._herdSharingSyncCoordinator = State(initialValue: sharingSyncCoordinator)
    }

    var body: some View {
        RootAppView(storageError: runtime.storageError, dataAccessMode: runtime.dataAccessMode)
            .environmentObject(tagColorLibrary)
            .environment(\.appDataAccessMode, runtime.dataAccessMode)
            .environment(\.recoveryModeController, runtime.dataAccessMode.isRecoveryMode ? recoveryModeController : nil)
            .environment(\.dashboardRecordReader, runtime.dependencies.dashboardRepository)
            .environment(\.fieldCheckOverviewReader, runtime.dependencies.fieldCheckRepository)
            .environment(\.workingProtocolTemplateReader, runtime.dependencies.workingRepository)
            .environment(\.syncDiagnosticsRepository, runtime.dependencies.syncDiagnosticsRepository)
            .environment(\.herdRepository, runtime.dependencies.herdRepository)
            .environment(\.herdSharingRepository, runtime.dependencies.herdSharingRepository)
            .environment(\.cloudKitShareInvitationCoordinator, cloudKitShareInvitationCoordinator)
            .environment(\.cloudKitShareAdapter, runtime.dependencies.cloudKitShareAdapter)
            .environment(\.herdSharingSyncCoordinator, herdSharingSyncCoordinator)
            .environment(\.herdCollaborationWritePolicy, runtime.dependencies.herdCollaborationWritePolicy)
            .environment(\.herdSharingConflictReviewStore, runtime.dependencies.herdSharingConflictReviewStore)
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
                if runtime.dataAccessMode.isRecoveryMode {
                    RecoveryModeBannerOverlay.shared.show(controller: recoveryModeController)
                } else {
                    await herdSharingSyncCoordinator.refreshSharingAccessNow(trigger: .appLaunch)
                    herdSharingSyncCoordinator.requestAutomaticSync(trigger: .appLaunch)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    guard runtime.dataAccessMode.allowsDataMutations else {
                        RecoveryModeBannerOverlay.shared.show(controller: recoveryModeController)
                        return
                    }
                    appSettingsSynchronizer.refreshFromICloudIfStarted()
                    tagColorLibrary.refresh()
                    Task { @MainActor in
                        await herdSharingSyncCoordinator.refreshSharingAccessNow(trigger: .appForeground)
                        herdSharingSyncCoordinator.requestAutomaticSync(trigger: .appForeground)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .yaHerdCloudKitShareAccepted)) { notification in
                guard runtime.dataAccessMode.allowsDataMutations else {
                    recoveryModeController.isPresentingCenter = true
                    return
                }
                if let metadata = notification.userInfo?[CloudKitShareNotificationUserInfoKey.metadata] as? CKShare.Metadata {
                    cloudKitShareInvitationCoordinator.recordAcceptedShare(metadata: metadata)
                }
                Task { @MainActor in
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
    let dataAccessMode: AppDataAccessMode
    @State private var showsStorageError: Bool

    init(storageError: String?, dataAccessMode: AppDataAccessMode) {
        self.storageError = storageError
        self.dataAccessMode = dataAccessMode
        self._showsStorageError = State(
            initialValue: storageError != nil && !dataAccessMode.isRecoveryMode
        )
    }

    var body: some View {
        MainTabView()
            .safeAreaInset(edge: .top, spacing: 0) {
                if dataAccessMode.isRecoveryMode {
                    Color.clear
                        .frame(height: RecoveryModePersistentBanner.reservedHeight)
                        .accessibilityHidden(true)
                }
            }
            .alert("Storage Mode Changed", isPresented: $showsStorageError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storageError ?? "The requested storage mode could not be opened.")
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
