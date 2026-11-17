//
//  yaHerdApp.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftUI

@main
struct yaHerdApp: App {
    @State private var bootstrapState: AppBootstrapState = .loading
    @State private var bootstrapStarted = false
    #if DEBUG
    @State private var developmentImportCheckInProgress = false
    #endif

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
                case .developmentImportPending:
                    ContentUnavailableView {
                        Label("Waiting for iCloud Herd", systemImage: "icloud.and.arrow.down")
                    } description: {
                        Text("The Herd or some of its related records have not finished importing. " +
                            "yaHerd is keeping iCloud active and will check again without " +
                            "creating or replacing any Herd data.")
                    } actions: {
                        Button("Check Again") {
                            Task { @MainActor in await retryPendingDevelopmentImport() }
                        }
                    }
                    .task {
                        // The development-only integration path must remain active
                        // until the imported root is complete. Check without
                        // reopening stores or creating any local Herd records.
                        while !Task.isCancelled {
                            do {
                                try await Task.sleep(for: .seconds(3))
                            } catch {
                                break
                            }
                            await retryPendingDevelopmentImport()
                            guard case .developmentImportPending = bootstrapState else {
                                break
                            }
                        }
                    }
                #endif
                }
            }
            .task {
                guard !bootstrapStarted else { return }
                bootstrapStarted = true
                bootstrapState = await Self.bootstrap()
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
            case .mirrored(let selectedHerdID):
                let cloudKitAssembly = try await CoreDataPersistenceAssembly.loadCloudKit(
                    storeURL: storeURL,
                    mirroringEnabled: true
                )
                do {
                    let candidate = try CoreDataAppPersistenceAssembly.resolveCloudKitHerdForChoice(
                        using: cloudKitAssembly,
                        privateStoreURL: storeURL,
                        requestedHerdID: selectedHerdID
                    )
                    // An imported Herd root may precede its child records.
                    // For a remembered selection, leave other accessible Herds
                    // usable through the chooser while this graph catches up.
                    if candidate.currentHerdSelection.currentHerdID != nil {
                        do {
                            try await CloudKitDevelopmentLaunch.validateHomeReadiness(candidate)
                        } catch {
                            guard selectedHerdID == nil,
                                  CloudKitDevelopmentLaunch.isImportPending(error) else {
                                throw error
                            }
                            candidate.currentHerdSelection.deferCurrentHerdUntilImportReady()
                        }
                    }
                    persistence = candidate
                } catch {
                    if CloudKitDevelopmentLaunch.isImportPending(error) {
                        AppLaunchDiagnostics.record(
                            actualStorageMode: .cloudKitDevelopmentBlocked
                        )
                        return .developmentImportPending(
                            CloudKitDevelopmentPendingImport(
                                assembly: cloudKitAssembly,
                                privateStoreURL: storeURL,
                                selectedHerdID: selectedHerdID
                            )
                        )
                    }
                    // Both stores opened successfully. A rejected import graph
                    // is not a SQLite failure and must not start recovery.
                    let message = CloudKitDevelopmentLaunch.nonStorageStartupMessage(
                        for: error
                    ) ?? error.localizedDescription
                    AppLaunchDiagnostics.record(
                        actualStorageMode: .cloudKitDevelopmentBlocked,
                        startupError: message
                    )
                    return .developmentMirroringBlocked(message)
                }
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
                        validateHerdReadiness: nil
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
        let dependencies = persistence.makeDependencies(dataAccessMode: .readWrite)
        AppLaunchDiagnostics.record(actualStorageMode: storageMode)
        #if DEBUG
        NSLog("yaHerd active storage mode: %@", storageMode.displayName)
        #endif
        let validateReadiness: (@MainActor (UUID) async throws -> Void)?
        #if DEBUG
        if storageMode == .cloudKitDevelopment {
            validateReadiness = { herdID in
                // The probe uses existing stores without changing the live selection.
                try await CloudKitDevelopmentLaunch.validateHomeReadiness(
                    persistence.makeReadinessCandidate(for: herdID)
                )
            }
        } else {
            validateReadiness = nil
        }
        #else
        validateReadiness = nil
        #endif
        return AppRuntime(
            persistenceLifetime: persistence,
            dependencies: dependencies,
            dataAccessMode: .readWrite,
            recoveryContext: nil,
            storageError: nil,
            herdSelection: persistence.currentHerdSelection,
            validateHerdReadiness: validateReadiness
        )
    }

    #if DEBUG
    @MainActor
    private func retryPendingDevelopmentImport() async {
        guard !developmentImportCheckInProgress,
              case .developmentImportPending(let pending) = bootstrapState else {
            return
        }
        developmentImportCheckInProgress = true
        defer { developmentImportCheckInProgress = false }

        do {
            let persistence = try CoreDataAppPersistenceAssembly.resolveCloudKitHerdForChoice(
                using: pending.assembly,
                privateStoreURL: pending.privateStoreURL,
                requestedHerdID: pending.selectedHerdID
            )
            if persistence.currentHerdSelection.currentHerdID != nil {
                try await CloudKitDevelopmentLaunch.validateHomeReadiness(persistence)
            }
            bootstrapState = .ready(Self.makeRuntime(
                persistence: persistence,
                storageMode: .cloudKitDevelopment
            ))
        } catch {
            guard !CloudKitDevelopmentLaunch.isImportPending(error) else {
                return
            }
            let message = CloudKitDevelopmentLaunch.nonStorageStartupMessage(for: error)
                ?? error.localizedDescription
            AppLaunchDiagnostics.record(
                actualStorageMode: .cloudKitDevelopmentBlocked,
                startupError: message
            )
            bootstrapState = .developmentMirroringBlocked(message)
        }
    }
    #endif
}

private enum AppBootstrapState {
    case loading
    case ready(AppRuntime)
    case storageUnavailable(String)
    case developmentMirroringBlocked(String)
    #if DEBUG
    case developmentImportPending(CloudKitDevelopmentPendingImport)
    #endif
}

#if DEBUG
@MainActor
private struct CloudKitDevelopmentPendingImport {
    let assembly: CoreDataPersistenceAssembly
    let privateStoreURL: URL
    let selectedHerdID: UUID?
}
#endif

private struct AppRuntime {
    // Retain the one Core Data assembly for the app lifetime. Presentation sees
    // only the persistence-neutral feature dependencies and access mode.
    let persistenceLifetime: any PersistenceAssembly
    let dependencies: AppDependencies
    let dataAccessMode: AppDataAccessMode
    let recoveryContext: RecoveryModeContext?
    let storageError: String?
    let herdSelection: AppCurrentHerdSelection
    let validateHerdReadiness: (@MainActor (UUID) async throws -> Void)?
}

private struct RunningAppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tagColorLibrary: TagColorLibraryStore
    @StateObject private var recoveryModeController: RecoveryModeController
    @State private var herdDirectory: HerdDirectoryController

    private let runtime: AppRuntime
    private let applicationSettings: ApplicationSettings

    init(
        runtime: AppRuntime,
        applicationSettings: ApplicationSettings
    ) {
        self.runtime = runtime
        self.applicationSettings = applicationSettings
        self._herdDirectory = State(initialValue: HerdDirectoryController(
            repository: runtime.dependencies.herdRepository,
            selection: runtime.herdSelection,
            validateReadiness: runtime.validateHerdReadiness
        ))
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
            .onChange(of: runtime.herdSelection.currentHerdID) { _, _ in
                tagColorLibrary.resetForHerdChange()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: CoreDataPersistentContainer.remoteStoreChangeNotification
                ).receive(on: DispatchQueue.main)
            ) { _ in
                // Remote imports and revoked shares may change membership
                // without a scene transition or an open Herd chooser.
                guard !runtime.dataAccessMode.isRecoveryMode else { return }
                herdDirectory.refresh(reportErrors: false)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    if !runtime.dataAccessMode.isRecoveryMode {
                        herdDirectory.refresh(reportErrors: false)
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
            } else {
                MainTabView()
                    // Discard old Herd drafts and view-owned async state.
                    .id(herdSelection.currentHerdID)
            }
        }
            .environment(navigation)
            .task {
                guard !hasRestoredNavigation else { return }
                guard dataAccessMode.isRecoveryMode || herdSelection.currentHerdID != nil else {
                    // No Herd-specific scene snapshot can be restored into the chooser.
                    return
                }
                navigation.selectedHerdID = herdSelection.currentHerdID
                let outcome = AppNavigationSceneStorageAccess.restore(
                    navigation: navigation,
                    from: navigationRestorationPayload,
                    using: navigationRestorationValidator,
                    dataAccessMode: dataAccessMode
                )
                hasRestoredNavigation = true
                guard let outcome else { return }
                navigationRestorationDeferred = outcome == .deferredValidation
                guard outcome == .applied,
                      let payload = AppNavigationSceneStorageAccess.payload(
                        for: navigation,
                        dataAccessMode: dataAccessMode
                      ) else { return }
                navigationRestorationPayload = payload
            }
            .onChange(of: herdSelection.currentHerdID) { _, newHerdID in
                navigation.resetForHerdChange(to: newHerdID)
                hasRestoredNavigation = true
                navigationRestorationDeferred = false
                if let payload = AppNavigationSceneStorageAccess.payload(
                    for: navigation,
                    dataAccessMode: dataAccessMode
                ) {
                    navigationRestorationPayload = payload
                }
            }
            .onChange(of: navigation.snapshot) { _, _ in
                guard hasRestoredNavigation, !dataAccessMode.isRecoveryMode else { return }

                // Only the durable runtime may replace a deferred snapshot after user navigation.
                navigationRestorationDeferred = false
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
                navigation.handle(url: url)
            }
            .alert("Storage Error", isPresented: $showsStorageError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(storageError ?? "Persistent storage could not be opened.")
            }
    }

    @MainActor
    private func retryDeferredNavigationRestoration() {
        guard hasRestoredNavigation,
              navigationRestorationDeferred,
              !dataAccessMode.isRecoveryMode,
              let activeHerdID = herdSelection.currentHerdID,
              navigation.selectedHerdID == activeHerdID else { return }

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
    case mirrored(selectedHerdID: UUID?)

    static func resolve(enabled: Bool, environment: [String: String]) throws -> Self {
        guard enabled else { return .disabled }
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
        if let fieldCheckError = error as? CoreDataFieldCheckMappingError {
            switch fieldCheckError {
            case .missingFindingSession, .missingAnimalCheckSession:
                return true
            default:
                return false
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

    var errorDescription: String? {
        switch self {
        case .invalidSelectedHerdID:
            return "YAHERD_SELECTED_ICLOUD_HERD_ID must be an existing Herd UUID. " +
                "Use it only with the signed development mirroring scheme to select a " +
                "specific owned or shared Herd. No Herd records were changed."
        }
    }
}
#endif
