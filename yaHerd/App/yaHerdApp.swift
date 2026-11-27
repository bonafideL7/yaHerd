//
//  yaHerdApp.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI

@main
struct yaHerdApp: App {
    @UIApplicationDelegateAdaptor(HerdInvitationAppDelegate.self) private var invitationDelegate
    @StateObject private var invitations = HerdInvitationInbox.shared
    @State private var bootstrapState: AppBootstrapState = .loading
    @State private var bootstrapStarted = false
    private let applicationSettings: ApplicationSettings

    init() {
        self.applicationSettings = ApplicationSettings()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch bootstrapState {
                case .loading:
                    ProgressView("Opening yaHerd…")

                case .ready(let runtime):
                    RunningAppView(
                        runtime: runtime,
                        applicationSettings: applicationSettings
                    )

                case .storageUnavailable(let message):
                    StartupStorageFailureView(message: message)

                case .developmentMirroringBlocked(let message):
                    ContentUnavailableView {
                        Label("iCloud Development Unavailable", systemImage: "icloud.slash")
                    } description: {
                        Text(message)
                    }

                #if DEBUG
                case .developmentSchemaResult(let message):
                    ContentUnavailableView {
                        Label("iCloud Schema Validation", systemImage: "icloud")
                    } description: {
                        Text(message)
                    }

                #endif
                }
            }
            .task {
                guard !bootstrapStarted else { return }
                bootstrapStarted = true
                bootstrapState = await Self.bootstrap()
                // Do not install an acceptance target until both stores have
                // finished loading; recovery and local-only launches fail closed.
                if case .ready(let runtime) = bootstrapState,
                   !runtime.dataAccessMode.isRecoveryMode,
                   runtime.persistenceLifetime.storageActivity.cloud != nil,
                   let persistence = runtime.persistenceLifetime as? CoreDataAppPersistenceAssembly {
                    invitations.install { invitation in
                        try await persistence.acceptHerdInvitation(invitation)
                        runtime.herdDirectory.refresh(reportErrors: false)
                    }
                } else {
                    invitations.install { _ in throw HerdInvitationError.unavailable }
                }
            }
            .alert("Herd Invitation", isPresented: Binding(
                get: { invitations.message != nil },
                set: { if !$0 { invitations.message = nil } }
            )) {
                Button("OK", role: .cancel) { invitations.message = nil }
            } message: {
                Text(invitations.message ?? "")
            }
        }
    }

    @MainActor
    private static func bootstrap() async -> AppBootstrapState {
        #if DEBUG
        // Only the explicitly named iCloud Development Xcode scheme enables
        // mirroring. No runtime variables or in-app preferences select a store.
        #if YAHERD_ICLOUD_DEVELOPMENT
        let developmentMirroringRequested = true
        #else
        let developmentMirroringRequested = false
        #endif
        #endif
        do {
            let storeURL = try CoreDataPersistentContainer.defaultStoreURL()
            let persistence: CoreDataAppPersistenceAssembly
            let storageMode: AppLaunchStorageMode
            #if DEBUG
            // Stage 2 mirroring is enabled only for the dedicated signed
            // iCloud Development scheme; normal Debug and Release stay local.
            switch try CloudKitDevelopmentLaunch.resolve(
                enabled: developmentMirroringRequested,
                environment: ProcessInfo.processInfo.environment
            ) {
            case .disabled:
                persistence = try await CoreDataAppPersistenceAssembly.load(
                    at: storeURL
                )
                storageMode = .local
            case .schemaValidation(let initialize):
                do {
                    try await CoreDataPersistentContainer.runDevelopmentSchemaValidation(
                        initialize: initialize
                    )
                    let message = initialize
                        ? "Development schema validation and initialization succeeded. No application Herd store was opened."
                        : "Development schema dry run succeeded. No schema records were uploaded."
                    AppLaunchDiagnostics.record(
                        actualStorageMode: .cloudKitSchemaValidation
                    )
                    NSLog("yaHerd: %@", message)
                    return .developmentSchemaResult(message)
                } catch {
                    let message = "Development schema validation failed: " + error.localizedDescription
                    AppLaunchDiagnostics.record(
                        actualStorageMode: .cloudKitDevelopmentBlocked,
                        startupError: message
                    )
                    return .developmentMirroringBlocked(message)
                }
            case .mirrored(let selectedHerdID):
                let cloudKitAssembly = try await CoreDataPersistenceAssembly.loadCloudKit(
                    storeURL: storeURL,
                    mirroringEnabled: true
                )
                let candidate = CoreDataAppPersistenceAssembly.resolveHerdForChoice(
                    using: cloudKitAssembly, requestedHerdID: selectedHerdID
                )
                // Keep the chooser and the opened stores available even when
                // the selected graph is incomplete or cannot safely be read.
                if candidate.currentHerdSelection.currentHerdID != nil {
                    do {
                        try await CloudKitDevelopmentLaunch.validateHomeReadiness(candidate)
                    } catch {
                        candidate.currentHerdSelection.deferCurrentHerdUntilImportReady()
                    }
                }
                persistence = candidate
                storageMode = .cloudKitDevelopment
            }
            #else
            persistence = try await CoreDataAppPersistenceAssembly.load(
                at: storeURL
            )
            storageMode = .local
            #endif
            return .ready(Self.makeRuntime(
                persistence: persistence,
                storageMode: storageMode
            ))
        } catch {
            #if DEBUG && YAHERD_ICLOUD_DEVELOPMENT
            // Only the dedicated mirrored build treats an import or activation
            // failure as an iCloud problem rather than a SQLite load failure.
            if let message = CloudKitDevelopmentLaunch.nonStorageStartupMessage(for: error) {
                AppLaunchDiagnostics.record(
                    actualStorageMode: .cloudKitDevelopmentBlocked,
                    startupError: message
                )
                return .developmentMirroringBlocked(message)
            }
            #endif
            let primaryError = error
            do {
                let persistence = try await CoreDataAppPersistenceAssembly.inMemoryRecovery()
                let startupMessage = """
                Persistent Core Data storage could not be opened. yaHerd is running in read-only recovery mode. Changes from this session will not be saved.

                Original error: \(primaryError.localizedDescription)
                """
                let dependencies = persistence.makeDependencies(
                    dataAccessMode: .recoveryReadOnly
                )
                AppLaunchDiagnostics.record(
                    actualStorageMode: .recovery,
                    startupError: startupMessage
                )
                return .ready(
                    AppRuntime(
                        persistenceLifetime: persistence,
                        dependencies: dependencies,
                        dataAccessMode: .recoveryReadOnly,
                        recoveryContext: RecoveryModeContext(
                            startupError: startupMessage
                        ),
                        storageError: startupMessage,
                        herdSelection: persistence.currentHerdSelection,
                        herdDirectory: HerdDirectoryController(
                            repository: dependencies.herdRepository,
                            selection: persistence.currentHerdSelection
                        ),
                        remoteHistory: nil
                    )
                )
            } catch {
                let startupMessage = """
                Persistent Core Data storage could not be opened, and the in-memory Core Data recovery store could not be started. No data was loaded and changes are disabled.

                Primary store error: \(primaryError.localizedDescription)
                In-memory recovery error: \(error.localizedDescription)
                """
                AppLaunchDiagnostics.record(
                    actualStorageMode: .unavailable,
                    startupError: startupMessage
                )
                return .storageUnavailable(startupMessage)
            }
        }
    }


    @MainActor
    private static func makeRuntime(
        persistence: CoreDataAppPersistenceAssembly,
        storageMode: AppLaunchStorageMode
    ) -> AppRuntime {
        if persistence.herdImportState.blocksHerdAccess {
            persistence.currentHerdSelection.deferCurrentHerdUntilImportReady()
        }
        let dependencies = persistence.makeDependencies(dataAccessMode: .readWrite)
        AppLaunchDiagnostics.record(actualStorageMode: storageMode)
        #if DEBUG
        NSLog("yaHerd active storage mode: %@", storageMode.displayName)
        #endif
        let validateReadiness: (@MainActor (AccessibleHerd) async throws -> Void)?
        #if DEBUG
        if storageMode == .cloudKitDevelopment {
            validateReadiness = { herd in
                // Probe the exact selected root without changing live selection.
                try await CloudKitDevelopmentLaunch.validateHomeReadiness(
                    persistence.makeReadinessCandidate(for: herd)
                )
            }
        } else {
            validateReadiness = nil
        }
        #else
        validateReadiness = nil
        #endif
        let herdDirectory = HerdDirectoryController(
            repository: dependencies.herdRepository,
            selection: persistence.currentHerdSelection,
            validateReadiness: validateReadiness,
            readImportState: { persistence.herdImportState }
        )
        let remoteHistory = persistence.makeRemoteHistoryCoordinator(
            mutationCenter: dependencies.applicationMutationCenter,
            herdDirectory: herdDirectory
        )
        return AppRuntime(
            persistenceLifetime: persistence,
            dependencies: dependencies,
            dataAccessMode: .readWrite,
            recoveryContext: nil,
            storageError: nil,
            herdSelection: persistence.currentHerdSelection,
            herdDirectory: herdDirectory,
            remoteHistory: remoteHistory
        )
    }

}

private enum AppBootstrapState {
    case loading
    case ready(AppRuntime)
    case storageUnavailable(String)
    case developmentMirroringBlocked(String)
    #if DEBUG
    case developmentSchemaResult(String)
    #endif
}

private struct AppRuntime {
    // Retain the one Core Data assembly for the app lifetime. Presentation sees
    // only the persistence-neutral feature dependencies and access mode.
    let persistenceLifetime: any PersistenceAssembly
    let dependencies: AppDependencies
    let dataAccessMode: AppDataAccessMode
    let recoveryContext: RecoveryModeContext?
    let storageError: String?
    let herdSelection: AppCurrentHerdSelection
    let herdDirectory: HerdDirectoryController
    let remoteHistory: AppRemoteHistoryCoordinator?
}

private struct RunningAppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tagColorLibrary: TagColorLibraryStore
    @StateObject private var recoveryModeController: RecoveryModeController
    @State private var storageActivity: StorageActivityController
    @State private var herdSharing: HerdSharingController
    private var herdDirectory: HerdDirectoryController { runtime.herdDirectory }

    private let runtime: AppRuntime
    private let applicationSettings: ApplicationSettings

    init(
        runtime: AppRuntime,
        applicationSettings: ApplicationSettings
    ) {
        self.runtime = runtime
        self.applicationSettings = applicationSettings
        self._storageActivity = State(initialValue: StorageActivityController(assembly: runtime.persistenceLifetime))
        self._herdSharing = State(initialValue: HerdSharingController(assembly: runtime.persistenceLifetime))
        self._tagColorLibrary = StateObject(
            wrappedValue: TagColorLibraryStore(
                repository: runtime.dependencies.tagColorRepository
            )
        )
        self._recoveryModeController = StateObject(
            wrappedValue: RecoveryModeController(
                context: runtime.recoveryContext ?? RecoveryModeContext(
                    startupError: "Recovery mode is not active."
                ),
                automaticallyRefreshDiagnostics: false
            )
        )
    }

    private var navigationRestorationValidator: RepositoryAppNavigationRestorationValidator {
        RepositoryAppNavigationRestorationValidator(
            herdRepository: runtime.dependencies.herdRepository,
            selection: runtime.herdSelection,
            animalRepository: runtime.dependencies.animalFeatureDependencies.detailRepository,
            pastureRepository: runtime.dependencies.pastureFeatureDependencies.existenceChecker,
            fieldCheckRepository: runtime.dependencies.fieldCheckFeatureDependencies.sessionDetailRepository,
            workingRepository: runtime.dependencies.workingSessionFeatureDependencies.sessionDetailRepository
        )
    }

    var body: some View {
        RootAppView(
            storageError: runtime.storageError,
            dataAccessMode: runtime.dataAccessMode,
            navigationRestorationValidator: navigationRestorationValidator,
            navigationMutationRevision: runtime.dependencies.applicationMutationCenter.currentSequence
        )
            .environment(applicationSettings)
            .environment(runtime.herdSelection)
            .environment(herdDirectory)
            .environment(storageActivity)
            .environment(herdSharing)
            .environmentObject(tagColorLibrary)
            .environment(\.appDataAccessMode, runtime.dataAccessMode)
            .environment(
                \.recoveryModeController,
                runtime.dataAccessMode.isRecoveryMode ? recoveryModeController : nil
            )
            .environment(\.homeFeatureDependencies, runtime.dependencies.homeFeatureDependencies)
            .environment(\.animalFeatureDependencies, runtime.dependencies.animalFeatureDependencies)
            .environment(\.pastureFeatureDependencies, runtime.dependencies.pastureFeatureDependencies)
            .environment(\.fieldCheckFeatureDependencies, runtime.dependencies.fieldCheckFeatureDependencies)
            .environment(
                \.workingSessionFeatureDependencies,
                runtime.dependencies.workingSessionFeatureDependencies
            )
            .onChange(of: runtime.dependencies.applicationMutationCenter.currentSequence) { _, _ in
                guard !runtime.dataAccessMode.isRecoveryMode,
                      runtime.herdSelection.currentHerdID != nil else { return }
                tagColorLibrary.refresh()
            }
            .onChange(of: runtime.herdSelection.selectionRevision) { _, _ in
                tagColorLibrary.resetForHerdChange()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: CoreDataPersistentContainer.remoteStoreChangeNotification
                ).receive(on: DispatchQueue.main)
            ) { _ in
                // Mirrored data changes are processed by the single history
                // consumer, which refreshes inventory before publication.
                guard !runtime.dataAccessMode.isRecoveryMode,
                      runtime.remoteHistory == nil else { return }
                herdDirectory.refresh(reportErrors: false)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: CoreDataPersistentContainer.herdImportStateChanged
                ).receive(on: DispatchQueue.main)
            ) { _ in
                guard !runtime.dataAccessMode.isRecoveryMode else { return }
                herdDirectory.refresh(reportErrors: false)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: CoreDataPersistentContainer.storageActivityChanged
                ).receive(on: DispatchQueue.main)
            ) { _ in
                storageActivity.refresh()
            }
            .task {
                storageActivity.refresh()
                guard !runtime.dataAccessMode.isRecoveryMode else { return }
                herdDirectory.refresh(reportErrors: false)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    storageActivity.refresh()
                    if !runtime.dataAccessMode.isRecoveryMode {
                        herdDirectory.refresh(reportErrors: false)
                        runtime.remoteHistory?.requestProcessing()
                    }
                    if runtime.herdSelection.currentHerdID != nil {
                        tagColorLibrary.refresh()
                    }
                }
            }
    }
}

/// Scene restoration is durable state, not part of the ephemeral recovery graph.
/// In recovery we neither read/validate the stored snapshot against a temporary
/// Herd nor write any transient navigation routes back into SceneStorage.
@MainActor
enum AppNavigationSceneStorageAccess {
    static func restore(
        navigation: AppNavigationState,
        from payload: String,
        using validator: any AppNavigationRestorationValidating,
        dataAccessMode: AppDataAccessMode
    ) -> AppNavigationRestoreOutcome? {
        guard !dataAccessMode.isRecoveryMode else { return nil }
        return navigation.restorePreservingStoredSnapshot(
            from: payload,
            using: validator
        )
    }

    /// The chooser may be shown before a remembered CloudKit Herd imports.
    /// On its first activation, validate the original scene payload against
    /// that Herd instead of replacing it with empty navigation.
    static func restoreForSelectedHerd(
        navigation: AppNavigationState,
        selectedHerdID: UUID?,
        selectedHerdRootIdentity: URL?,
        from payload: String,
        using validator: any AppNavigationRestorationValidating,
        dataAccessMode: AppDataAccessMode
    ) -> AppNavigationRestoreOutcome? {
        navigation.selectedHerdID = selectedHerdID
        navigation.selectedHerdRootIdentity = selectedHerdRootIdentity
        return restore(
            navigation: navigation,
            from: payload,
            using: validator,
            dataAccessMode: dataAccessMode
        )
    }

    /// The first selection itself is not a user navigation decision. While
    /// record validation is pending, only an actual subsequent navigation
    /// change may replace the previously saved scene payload.
    static func shouldPersistNavigation(
        snapshot: AppNavigationSnapshot,
        deferredBaseline: AppNavigationSnapshot?,
        isRestorationDeferred: Bool
    ) -> Bool {
        !isRestorationDeferred || snapshot != deferredBaseline
    }

    static func payload(
        for navigation: AppNavigationState,
        dataAccessMode: AppDataAccessMode
    ) -> String? {
        guard !dataAccessMode.isRecoveryMode else { return nil }
        return navigation.restorationPayload()
    }
}

private struct RootAppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppCurrentHerdSelection.self) private var herdSelection

    let storageError: String?
    let dataAccessMode: AppDataAccessMode
    let navigationRestorationValidator: any AppNavigationRestorationValidating
    let navigationMutationRevision: UInt64

    @State private var showsStorageError: Bool
    @State private var navigation = AppNavigationState()
    @State private var hasRestoredNavigation = false
    @State private var navigationRestorationDeferred = false
    @State private var deferredNavigationBaseline: AppNavigationSnapshot?
    @SceneStorage("navigation.restoration.v1") private var navigationRestorationPayload = ""

    init(
        storageError: String?,
        dataAccessMode: AppDataAccessMode,
        navigationRestorationValidator: any AppNavigationRestorationValidating,
        navigationMutationRevision: UInt64
    ) {
        self.storageError = storageError
        self.dataAccessMode = dataAccessMode
        self.navigationRestorationValidator = navigationRestorationValidator
        self.navigationMutationRevision = navigationMutationRevision
        self._showsStorageError = State(
            initialValue: storageError != nil && !dataAccessMode.isRecoveryMode
        )
    }

    var body: some View {
        Group {
            if herdSelection.currentHerdID == nil && !dataAccessMode.isRecoveryMode {
                NavigationStack {
                    HerdDirectoryView()
                }
            } else if !dataAccessMode.isRecoveryMode && (
                !hasRestoredNavigation || navigation.selectedHerdID != herdSelection.currentHerdID ||
                navigation.selectedHerdRootIdentity != herdSelection.selectedRootIdentity
            ) {
                ProgressView("Opening Herd…")
            } else {
                MainTabView()
                    // Discard old Herd drafts and async state even after A → B → A.
                    .id(herdSelection.selectionRevision)
            }
        }
            .environment(navigation)
            .task {
                guard !hasRestoredNavigation else { return }
                guard dataAccessMode.isRecoveryMode || herdSelection.currentHerdID != nil else {
                    // The original scene payload must survive the chooser until
                    // a Herd is selected and its records can be validated.
                    return
                }
                restoreInitialNavigation(for: herdSelection.currentHerdID)
            }
            .onChange(of: herdSelection.selectionRevision) { _, _ in
                if !hasRestoredNavigation, !dataAccessMode.isRecoveryMode {
                    guard let selectedHerdID = herdSelection.currentHerdID else { return }
                    // The first selection after an import-pending chooser is
                    // the delayed startup, not a switch away from an open Herd.
                    restoreInitialNavigation(for: selectedHerdID)
                    return
                }
                navigation.resetForHerdChange(
                    to: herdSelection.currentHerdID,
                    rootIdentity: herdSelection.selectedRootIdentity,
                    force: true
                )
                hasRestoredNavigation = true
                navigationRestorationDeferred = false
                deferredNavigationBaseline = nil
                if let payload = AppNavigationSceneStorageAccess.payload(
                    for: navigation,
                    dataAccessMode: dataAccessMode
                ) {
                    navigationRestorationPayload = payload
                }
            }
            .onChange(of: navigation.snapshot) { _, newSnapshot in
                guard hasRestoredNavigation, !dataAccessMode.isRecoveryMode else { return }

                guard AppNavigationSceneStorageAccess.shouldPersistNavigation(
                    snapshot: newSnapshot,
                    deferredBaseline: deferredNavigationBaseline,
                    isRestorationDeferred: navigationRestorationDeferred
                ) else { return }

                // Explicit navigation may replace a deferred snapshot; the
                // automatic first Herd activation itself must not.
                navigationRestorationDeferred = false
                deferredNavigationBaseline = nil
                guard let payload = AppNavigationSceneStorageAccess.payload(
                    for: navigation,
                    dataAccessMode: dataAccessMode
                ) else { return }
                navigationRestorationPayload = payload
            }
            .onChange(of: navigationMutationRevision) { _, _ in
                guard hasRestoredNavigation, !dataAccessMode.isRecoveryMode else { return }

                if navigationRestorationDeferred {
                    retryDeferredNavigationRestoration()
                    return
                }
                navigation.revalidateIdentityBoundState(using: navigationRestorationValidator)
                if let payload = AppNavigationSceneStorageAccess.payload(
                    for: navigation,
                    dataAccessMode: dataAccessMode
                ) {
                    navigationRestorationPayload = payload
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: CoreDataPersistentContainer.remoteStoreChangeNotification
                ).receive(on: DispatchQueue.main)
            ) { _ in
                // Stage 3 retries only a pending scene restoration; broad remote
                // feature invalidation belongs to the later history work.
                retryDeferredNavigationRestoration()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    retryDeferredNavigationRestoration()
                }
            }
            .onOpenURL { url in
                navigation.handle(url: url, using: navigationRestorationValidator)
            }
            .alert("Storage Error", isPresented: $showsStorageError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storageError ?? "Persistent storage could not be opened.")
            }
    }

    @MainActor
    private func restoreInitialNavigation(for selectedHerdID: UUID?) {
        let outcome = AppNavigationSceneStorageAccess.restoreForSelectedHerd(
            navigation: navigation,
            selectedHerdID: selectedHerdID,
            selectedHerdRootIdentity: herdSelection.selectedRootIdentity,
            from: navigationRestorationPayload,
            using: navigationRestorationValidator,
            dataAccessMode: dataAccessMode
        )
        hasRestoredNavigation = true
        guard let outcome else { return }

        navigationRestorationDeferred = outcome == .deferredValidation
        deferredNavigationBaseline = navigationRestorationDeferred ? navigation.snapshot : nil
        guard outcome == .applied,
              let payload = AppNavigationSceneStorageAccess.payload(
                for: navigation,
                dataAccessMode: dataAccessMode
              ) else { return }
        navigationRestorationPayload = payload
    }

    @MainActor
    private func retryDeferredNavigationRestoration() {
        guard hasRestoredNavigation,
              navigationRestorationDeferred,
              !dataAccessMode.isRecoveryMode,
              let activeHerdID = herdSelection.currentHerdID,
              navigation.selectedHerdID == activeHerdID,
              navigation.selectedHerdRootIdentity == herdSelection.selectedRootIdentity else { return }

        let outcome = navigation.restorePreservingStoredSnapshot(
            from: navigationRestorationPayload,
            using: navigationRestorationValidator
        )
        navigationRestorationDeferred = outcome == .deferredValidation
        guard outcome == .applied,
              let payload = AppNavigationSceneStorageAccess.payload(
                  for: navigation,
                  dataAccessMode: dataAccessMode
              ) else { return }
        deferredNavigationBaseline = nil
        navigationRestorationPayload = payload
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

#if DEBUG
/// Dedicated development build config enables the mirrored store topology.
/// No UI preferences or Xcode Run arguments can silently switch modes.
enum CloudKitDevelopmentLaunch: Equatable {
    case disabled
    case schemaValidation(initialize: Bool)
    case mirrored(selectedHerdID: UUID?)

    static func resolve(enabled: Bool, environment: [String: String]) throws -> Self {
        guard enabled else { return .disabled }
        let initialize = environment["YAHERD_CREATE_ICLOUD_DEV_SCHEMA"] == "1"
        if initialize || environment["YAHERD_VALIDATE_ICLOUD_SCHEMA"] == "1" {
            return .schemaValidation(initialize: initialize)
        }
        guard environment["YAHERD_ICLOUD_SCHEMA_VALIDATED"] == "1" else {
            throw CloudKitDevelopmentLaunchError.schemaValidationRequired
        }
        if let rawHerdID = environment["YAHERD_SELECTED_ICLOUD_HERD_ID"] {
            guard let selectedHerdID = UUID(uuidString: rawHerdID) else {
                throw CloudKitDevelopmentLaunchError.invalidSelectedHerdID
            }
            return .mirrored(selectedHerdID: selectedHerdID)
        }
        return .mirrored(selectedHerdID: nil)
    }

    @MainActor
    static func validateHomeReadiness(
        _ persistence: CoreDataAppPersistenceAssembly
    ) async throws {
        let home = persistence.makeDependencies(
            dataAccessMode: .readWrite
        ).homeFeatureDependencies
        _ = try await LoadHomeUseCase(
            dashboardRepository: home.dashboardQueryReader,
            fieldCheckRepository: home.homeFieldCheckQueryReader,
            workingRepository: home.homeWorkingQueryReader
        ).execute(configuration: DashboardConfiguration())
    }

    static func isImportPending(_ error: Error) -> Bool {
        if (error as? HerdRepositoryError) == .missingHerd
            || error is CoreDataHerdMappingError {
            return true
        }
        // Only a missing Herd link is an expected partially imported graph.
        // An explicit other-Herd link is a real isolation violation.
        if let readError = error as? CoreDataReadModelError,
           case .invalidHerdOwnership(_, _, _, let actualHerdID) = readError {
            return actualHerdID == nil
        }
        if let persistenceError = error as? CoreDataPersistenceError,
           case .missingApplicationID = persistenceError {
            return true
        }
        if let animalError = error as? CoreDataAnimalRepositoryError {
            switch animalError {
            case .missingHealthDate, .missingHealthAnimalRelationship,
                 .missingPregnancyAnimalRelationship, .missingTagAssignmentDate,
                 .missingAnimalTagNumber, .missingAnimalEditorRevision,
                 .missingAnimalHerdRelationship, .missingAnimalBirthDate,
                 .missingPregnancyDate, .missingMovementDate,
                 .missingMovementAnimalRelationship, .missingStatusHistoryDate,
                 .missingStatusHistoryAnimalRelationship:
                return true
            case .invalidAnimalStatusRawValue(_, let value),
                 .invalidStatusHistoryRawValue(_, let value):
                return value == nil
            default:
                return false
            }
        }
        if let fieldCheckError = error as? CoreDataFieldCheckMappingError {
            switch fieldCheckError {
            case .missingFindingSession, .missingAnimalCheckSession,
                 .missingFindingDate, .missingSessionStartDate, .missingAnimalIDSnapshot:
                return true
            case .invalidFindingType(_, let value), .invalidFindingStatus(_, let value),
                 .invalidAnimalType(_, let value):
                return value == nil
            default:
                return false
            }
        }
        if let workingError = error as? CoreDataWorkingMappingError {
            switch workingError {
            case .missingQueueAnimalID, .missingTreatmentDate, .missingSessionDate:
                return true
            case .invalidSessionStatus(_, let value), .invalidQueueStatus(_, let value):
                return value == nil
            default:
                return false
            }
        }
        if let workingError = error as? CoreDataWorkingRepositoryError {
            switch workingError {
            case .missingTreatmentSession, .missingQueueSession:
                return true
            case .invalidHerdOwnership(_, _, let actual),
                 .invalidSessionRelationship(_, _, let actual):
                return actual == nil
            default:
                return false
            }
        }
        if let tagError = error as? CoreDataTagColorRepositoryError {
            switch tagError {
            case .missingTagAnimal, .missingName, .missingCreatedAt, .missingUpdatedAt:
                return true
            }
        }
        return false
    }

    static func nonStorageStartupMessage(for error: Error) -> String? {
        if let configurationError = error as? CloudKitDevelopmentLaunchError {
            return configurationError.localizedDescription
        }
        if error as? HerdRepositoryError == .missingHerd {
            return "The selected or default Herd is not available yet. It may still " +
                "be importing. No replacement Herd was created. Relaunch yaHerd " +
                "to check again."
        }
        if error is CoreDataHerdMappingError {
            return "A Herd is missing required fields. Its import may be " +
                "incomplete. No data was changed. Relaunch yaHerd to check again."
        }
        if error is CoreDataAppHerdBootstrapError {
            return "More than one owned Herd exists. Automatic development " +
                "selection cannot choose one; no Herd data was changed."
        }
        if let readError = error as? CoreDataReadModelError {
            if case .invalidHerdOwnership(
                let entity, let id, let expected, let actual
            ) = readError {
                return "Cannot open imported \(entity) \(id): Herd link is " +
                    "\(actual?.uuidString ?? "missing"), expected \(expected.uuidString). " +
                    "No records were changed."
            }
            return "The imported Herd cannot safely open: \(readError.localizedDescription) " +
                "No data was changed. Check the development iCloud records and ownership."
        }
        if let persistenceError = error as? CoreDataPersistenceError {
            switch persistenceError {
            case .duplicateApplicationID:
                return "Duplicate application IDs prevent safe Herd selection. " +
                    "No Herd was selected or modified. Resolve the duplicate " +
                    "identity before using development iCloud mirroring."
            case .unresolvedHerdStore:
                return "The selected Herd's owning persistent store could not " +
                    "be resolved. No Herd was selected or modified."
            default:
                break
            }
        }
        return nil
    }
}

enum CloudKitDevelopmentLaunchError: LocalizedError, Equatable {
    case invalidSelectedHerdID
    case schemaValidationRequired

    var errorDescription: String? {
        switch self {
        case .schemaValidationRequired:
            return "Run signed development schema validation using YAHERD_VALIDATE_ICLOUD_SCHEMA=1 " +
                "and initialize the development schema if needed. After successful validation, " +
                "enable YAHERD_ICLOUD_SCHEMA_VALIDATED=1 in the iCloud Development Run scheme. " +
                "No Herd stores were opened."
        case .invalidSelectedHerdID:
            return "YAHERD_SELECTED_ICLOUD_HERD_ID must be an existing Herd UUID. " +
                "Use it only with the signed development mirroring scheme to select a " +
                "specific owned or shared Herd. No Herd records were changed."
        }
    }
}
#endif
