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

    var body: some Scene {
        WindowGroup {
            AppStartupView()
        }
    }

    @MainActor
    fileprivate static func bootstrap() async -> AppBootstrapState {
        let applicationSettings = ApplicationSettings()
        let appSettingsSynchronizer = AppSettingsSynchronizer(settings: applicationSettings)
        let syncMode = applicationSettings.syncMode

        do {
            ReliabilityLog.persistenceEvent(
                "AppStartup.openContainer.begin",
                detail: syncMode.rawValue
            )
            let container = try await Task { @concurrent in
                try ModelContainerFactory.makeContainer(syncMode: syncMode)
            }.value
            ReliabilityLog.persistenceEvent(
                "AppStartup.openContainer.complete",
                detail: syncMode.rawValue
            )

            try Self.runStartupDataMigrations(in: container.mainContext, syncMode: syncMode)

            AppLaunchDiagnostics.record(
                requestedSyncMode: syncMode,
                actualStorageMode: syncMode == .iCloud ? .iCloud : .localOnly,
                cloudKitOpened: syncMode == .iCloud
            )

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
                ),
                applicationSettings,
                appSettingsSynchronizer
            )
        } catch {
            let primaryError = error
            ReliabilityLog.persistenceFailure("AppStartup.openPrimaryContainer", error: error)

            if syncMode == .iCloud {
                applicationSettings.syncMode = .localOnly
                appSettingsSynchronizer.stop()

                do {
                    ReliabilityLog.persistenceEvent(
                        "AppStartup.openContainer.begin",
                        detail: SyncMode.localOnly.rawValue
                    )
                    let localContainer = try await Task { @concurrent in
                        try ModelContainerFactory.makeContainer(syncMode: .localOnly)
                    }.value
                    ReliabilityLog.persistenceEvent(
                        "AppStartup.openContainer.complete",
                        detail: SyncMode.localOnly.rawValue
                    )

                    try Self.runStartupDataMigrations(
                        in: localContainer.mainContext,
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
                        ),
                        applicationSettings,
                        appSettingsSynchronizer
                    )
                } catch {
                    let localRecoveryError = error
                    ReliabilityLog.persistenceFailure("AppStartup.openLocalFallbackContainer", error: error)

                    do {
                        let fallbackContainer = try await Task { @concurrent in
                            try ModelContainerFactory.makeRecoveryContainer()
                        }.value

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
                            ),
                            applicationSettings,
                            appSettingsSynchronizer
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
                let fallbackContainer = try await Task { @concurrent in
                    try ModelContainerFactory.makeRecoveryContainer()
                }.value

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
                    ),
                    applicationSettings,
                    appSettingsSynchronizer
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

    private static func runStartupDataMigrations(in context: ModelContext, syncMode: SyncMode) throws {
        try DefaultHerdBootstrapper.ensureDefaultHerdForAppLaunch(
            in: context,
            storageScope: syncMode.rawValue
        )
        try Self.ensureTagColorLibraryExistsForAppLaunch(in: context)
    }

    private static func ensureTagColorLibraryExistsForAppLaunch(in context: ModelContext) throws {
        var descriptor = FetchDescriptor<TagColorDefinition>()
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }

        // Do not create or normalize records while duplicate-ID repair is waiting for bridge
        // convergence. Startup should be able to display the existing graph without entering the
        // normal collaboration save pipeline.
        guard !HerdDataMutationGate().requiresBridgeConvergence else { return }

        for defaultColor in TagColorDefaults.seedDefaultColors() {
            try context.insertIntoDefaultHerd(TagColorDefinition(snapshot: defaultColor))
        }
        if context.hasChanges {
            try PersistenceLog.save(context, operation: "AppStartup.seedTagColors")
        }
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

fileprivate enum AppBootstrapState {
    case ready(AppRuntime, ApplicationSettings, AppSettingsSynchronizer)
    case storageUnavailable(String)
}

fileprivate struct AppRuntime {
    let modelContainer: ModelContainer
    let dependencies: AppDependencies
    let syncMode: SyncMode
    let dataAccessMode: AppDataAccessMode
    let recoveryContext: RecoveryModeContext?
    let storageError: String?
}

private struct AppStartupView: View {
    @State private var bootstrapState: AppBootstrapState?

    var body: some View {
        Group {
            if let bootstrapState {
                switch bootstrapState {
                case .ready(let runtime, let applicationSettings, let appSettingsSynchronizer):
                    RunningAppView(
                        runtime: runtime,
                        applicationSettings: applicationSettings,
                        appSettingsSynchronizer: appSettingsSynchronizer
                    )

                case .storageUnavailable(let message):
                    StartupStorageFailureView(message: message)
                }
            } else {
                StartupLoadingView()
            }
        }
        .task {
            guard bootstrapState == nil else { return }

            // Yield twice so the startup placeholder is committed to a frame before any app
            // services are constructed. Persistent store construction itself then runs on an
            // explicitly concurrent executor so SQLite/CloudKit initialization cannot block the
            // main actor.
            await Task.yield()
            await Task.yield()
            bootstrapState = await yaHerdApp.bootstrap()
        }
    }
}

private struct StartupLoadingView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Opening yaHerd…")
                    .font(.headline)
                Text("Loading local herd data")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

private struct RunningAppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tagColorLibrary: TagColorLibraryStore
    @StateObject private var recoveryModeController: RecoveryModeController
    @State private var cloudKitShareInvitationCoordinator: CloudKitShareInvitationCoordinator
    @State private var herdSharingSyncCoordinator: HerdSharingSyncCoordinator
    @State private var showsPendingCloudKitShareInvitation = false
    @State private var hasRunPostLaunchSetup = false

    private let runtime: AppRuntime
    private let applicationSettings: ApplicationSettings
    private let appSettingsSynchronizer: AppSettingsSynchronizer

    init(
        runtime: AppRuntime,
        applicationSettings: ApplicationSettings,
        appSettingsSynchronizer: AppSettingsSynchronizer
    ) {
        self.runtime = runtime
        self.applicationSettings = applicationSettings
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
                automaticallyRefreshDiagnostics: false
            )
        )
        let sharingSyncCoordinator = HerdSharingSyncCoordinator(
            herdRepository: runtime.dependencies.herdRepository,
            sharingRepository: runtime.dependencies.herdSharingRepository,
            storageMode: runtime.syncMode.herdStorageMode,
            writePolicy: runtime.dependencies.herdCollaborationWritePolicy,
            mutationGate: runtime.dependencies.herdDataMutationGate,
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

    private var collaborationDependencies: CollaborationDependencies {
        CollaborationDependencies(
            herdRepository: runtime.dependencies.herdRepository,
            sharingRepository: runtime.dependencies.herdSharingRepository,
            invitationCoordinator: cloudKitShareInvitationCoordinator,
            shareAdapter: runtime.dependencies.cloudKitShareAdapter,
            syncCoordinator: herdSharingSyncCoordinator,
            writePolicy: runtime.dependencies.herdCollaborationWritePolicy,
            conflictReviewStore: runtime.dependencies.herdSharingConflictReviewStore,
            diagnosticsRepository: runtime.dependencies.syncDiagnosticsRepository,
            settingsSynchronizer: appSettingsSynchronizer
        )
    }

    private var navigationRestorationValidator: RepositoryAppNavigationRestorationValidator {
        RepositoryAppNavigationRestorationValidator(
            herdRepository: runtime.dependencies.herdRepository,
            animalRepository: runtime.dependencies.animalFeatureDependencies.detailRepository,
            pastureRepository: runtime.dependencies.pastureFeatureDependencies.detailRepository,
            fieldCheckRepository: runtime.dependencies.fieldCheckFeatureDependencies.sessionDetailRepository,
            workingRepository: runtime.dependencies.workingSessionFeatureDependencies.sessionDetailRepository
        )
    }

    var body: some View {
        RootAppView(
            storageError: runtime.storageError,
            dataAccessMode: runtime.dataAccessMode,
            navigationRestorationValidator: navigationRestorationValidator,
            identityMutationRevision: runtime.dependencies.applicationMutationCenter.identityRevision
        )
            .environment(applicationSettings)
            .environmentObject(tagColorLibrary)
            .environment(\.appDataAccessMode, runtime.dataAccessMode)
            .environment(\.recoveryModeController, runtime.dataAccessMode.isRecoveryMode ? recoveryModeController : nil)
            .environment(\.homeFeatureDependencies, runtime.dependencies.homeFeatureDependencies)
            .environment(\.animalFeatureDependencies, runtime.dependencies.animalFeatureDependencies)
            .environment(\.pastureFeatureDependencies, runtime.dependencies.pastureFeatureDependencies)
            .environment(\.fieldCheckFeatureDependencies, runtime.dependencies.fieldCheckFeatureDependencies)
            .environment(\.workingSessionFeatureDependencies, runtime.dependencies.workingSessionFeatureDependencies)
            .environment(\.collaborationDependencies, collaborationDependencies)
            .modelContainer(runtime.modelContainer)
            .task {
                guard !hasRunPostLaunchSetup else { return }
                hasRunPostLaunchSetup = true
                guard runtime.dataAccessMode.allowsDataMutations else { return }

                appSettingsSynchronizer.startIfNeeded(syncMode: runtime.syncMode)

                // Historical Field Check snapshot repair is maintenance, not a prerequisite for
                // rendering the app. Run it only after the root UI exists so an older data set
                // cannot turn launch into a black screen.
                await Task.yield()
                do {
                    try FieldCheckHistoricalSnapshotMigrator.runIfNeeded(
                        in: runtime.modelContainer.mainContext,
                        storageScope: runtime.syncMode.rawValue
                    )
                } catch {
                    ReliabilityLog.persistenceFailure(
                        "AppStartup.fieldCheckHistoricalSnapshotMigration",
                        error: error
                    )
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    guard runtime.dataAccessMode.allowsDataMutations else { return }
                    appSettingsSynchronizer.refreshFromICloudIfStarted()
                    tagColorLibrary.refresh()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .yaHerdCloudKitShareAccepted)) { notification in
                guard runtime.dataAccessMode.allowsDataMutations else { return }
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
    let navigationRestorationValidator: any AppNavigationRestorationValidating
    let identityMutationRevision: UInt64

    @State private var showsStorageError: Bool
    @State private var navigation = AppNavigationState()
    @State private var hasRestoredNavigation = false
    @State private var navigationRestorationDeferred = false
    @SceneStorage("navigation.restoration.v1") private var navigationRestorationPayload = ""

    init(
        storageError: String?,
        dataAccessMode: AppDataAccessMode,
        navigationRestorationValidator: any AppNavigationRestorationValidating,
        identityMutationRevision: UInt64
    ) {
        self.storageError = storageError
        self.dataAccessMode = dataAccessMode
        self.navigationRestorationValidator = navigationRestorationValidator
        self.identityMutationRevision = identityMutationRevision
        self._showsStorageError = State(
            initialValue: storageError != nil && !dataAccessMode.isRecoveryMode
        )
    }

    var body: some View {
        MainTabView()
            .environment(navigation)
            .task {
                guard !hasRestoredNavigation else { return }
                let outcome = navigation.restorePreservingStoredSnapshot(
                    from: navigationRestorationPayload,
                    using: navigationRestorationValidator
                )
                hasRestoredNavigation = true
                navigationRestorationDeferred = outcome == .deferredValidation
                guard outcome == .applied else { return }
                navigationRestorationPayload = navigation.restorationPayload() ?? ""
            }
            .onChange(of: navigation.snapshot) { _, _ in
                guard hasRestoredNavigation else { return }

                // If startup validation was deferred, an explicit navigation change means the
                // user has chosen a new current state. Let that supersede the older stored snapshot
                // rather than restoring it later and unexpectedly navigating the user backwards.
                navigationRestorationDeferred = false
                guard let payload = navigation.restorationPayload() else { return }
                navigationRestorationPayload = payload
            }
            .onChange(of: identityMutationRevision) { _, _ in
                guard hasRestoredNavigation else { return }

                if navigationRestorationDeferred {
                    let outcome = navigation.restorePreservingStoredSnapshot(
                        from: navigationRestorationPayload,
                        using: navigationRestorationValidator
                    )
                    navigationRestorationDeferred = outcome == .deferredValidation
                    guard outcome == .applied else { return }
                } else {
                    navigation.revalidateIdentityBoundState(
                        using: navigationRestorationValidator
                    )
                }
                navigationRestorationPayload = navigation.restorationPayload() ?? ""
            }
            .onOpenURL { url in
                navigation.handle(url: url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .yaHerdNavigationRequest)) { notification in
                guard let request = notification.object as? AppNavigationRequest else { return }
                navigation.handle(request)
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
