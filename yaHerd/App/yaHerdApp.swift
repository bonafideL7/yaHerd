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
                case .herdSelection(let directory):
                    CloudKitDevelopmentHerdSelectionView(
                        directory: directory,
                        selectHerd: { herdID in
                            try await selectDevelopmentHerd(
                                herdID, directory: directory
                            )
                        }
                    )

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
                // A new device may have no imported roots or several owned
                // and joined Herds. Require a selection instead of guessing
                // or creating a replacement during CloudKit import.
                guard let selectedHerdID else {
                    return .herdSelection(CloudKitDevelopmentHerdDirectory(
                        assembly: cloudKitAssembly,
                        privateStoreURL: storeURL
                    ))
                }
                do {
                    let candidate = try CoreDataAppPersistenceAssembly.resolveCloudKitHerd(
                        using: cloudKitAssembly,
                        privateStoreURL: storeURL,
                        selectedHerdID: selectedHerdID
                    )
                    // An imported root can arrive before its owned records
                    // and relationships. Preserve the mirroring engine and
                    // defer Home instead of presenting partial data as corrupt.
                    try await CloudKitDevelopmentLaunch.validateHomeReadiness(candidate)
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
                        storageError: startupMessage
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
        return AppRuntime(
            persistenceLifetime: persistence,
            dependencies: dependencies,
            dataAccessMode: .readWrite,
            recoveryContext: nil,
            storageError: nil
        )
    }

    #if DEBUG
    @MainActor
    private func selectDevelopmentHerd(
        _ herdID: UUID,
        directory: CloudKitDevelopmentHerdDirectory
    ) async throws {
        guard case .herdSelection(let activeDirectory) = bootstrapState,
              activeDirectory.assembly === directory.assembly else {
            return
        }
        do {
            let persistence = try CoreDataAppPersistenceAssembly.resolveCloudKitHerd(
                using: directory.assembly,
                privateStoreURL: directory.privateStoreURL,
                selectedHerdID: herdID
            )
            try await CloudKitDevelopmentLaunch.validateHomeReadiness(persistence)
            bootstrapState = .ready(Self.makeRuntime(
                persistence: persistence,
                storageMode: .cloudKitDevelopment
            ))
        } catch {
            if CloudKitDevelopmentLaunch.isImportPending(error) {
                bootstrapState = .developmentImportPending(
                    CloudKitDevelopmentPendingImport(
                        assembly: directory.assembly,
                        privateStoreURL: directory.privateStoreURL,
                        selectedHerdID: herdID
                    )
                )
            } else {
                // An unavailable/corrupt candidate must not force a different
                // Herd to be selected. Keep the directory so another Herd can
                // be opened without closing the persistent stores.
                throw error
            }
        }
    }

    @MainActor
    private func retryPendingDevelopmentImport() async {
        guard !developmentImportCheckInProgress,
              case .developmentImportPending(let pending) = bootstrapState else {
            return
        }
        developmentImportCheckInProgress = true
        defer { developmentImportCheckInProgress = false }

        do {
            let persistence = try CoreDataAppPersistenceAssembly.resolveCloudKitHerd(
                using: pending.assembly,
                privateStoreURL: pending.privateStoreURL,
                selectedHerdID: pending.selectedHerdID
            )
            try await CloudKitDevelopmentLaunch.validateHomeReadiness(persistence)
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
    case herdSelection(CloudKitDevelopmentHerdDirectory)
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
}

private struct RunningAppView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tagColorLibrary: TagColorLibraryStore
    @StateObject private var recoveryModeController: RecoveryModeController

    private let runtime: AppRuntime
    private let applicationSettings: ApplicationSettings

    init(
        runtime: AppRuntime,
        applicationSettings: ApplicationSettings
    ) {
        self.runtime = runtime
        self.applicationSettings = applicationSettings
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
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    tagColorLibrary.refresh()
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
        MainTabView()
            .environment(navigation)
            .task {
                guard !hasRestoredNavigation else { return }
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
                if let payload = AppNavigationSceneStorageAccess.payload(
                    for: navigation,
                    dataAccessMode: dataAccessMode
                ) {
                    navigationRestorationPayload = payload
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
/// Retains both loaded stores while the user chooses a complete Herd root.
/// Discovery never creates a default Herd, even before iCloud import finishes.
@MainActor
struct CloudKitDevelopmentHerdDirectory {
    let assembly: CoreDataPersistenceAssembly
    let privateStoreURL: URL

    func fetchHerds() throws -> [AccessibleHerd] {
        try CoreDataHerdRepository(
            selection: AppCurrentHerdSelection(),
            assembly: assembly
        ).fetchAccessibleHerds()
    }

    func createHerd(named name: String) async throws -> HerdSummary {
        try await CoreDataHerdRepository(
            selection: AppCurrentHerdSelection(),
            assembly: assembly
        ).createOwnedHerd(named: name)
    }
}

/// Stage 3 selection entry for the signed development configuration. Normal
/// local-only launch is unchanged. Share invitation acceptance is Stage 5.
private struct CloudKitDevelopmentHerdSelectionView: View {
    let directory: CloudKitDevelopmentHerdDirectory
    let selectHerd: @MainActor (UUID) async throws -> Void

    @State private var herds: [AccessibleHerd] = []
    @State private var newHerdName = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Available Herds") {
                    if herds.isEmpty {
                        Text("No complete Herds are available yet. iCloud may still be importing.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(herds) { herd in
                        Button {
                            Task { @MainActor in await open(herd.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(herd.name)
                                    .foregroundStyle(.primary)
                                Text(herd.category == .owned ? "Owned Herd" : "Shared Herd")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isBusy)
                    }
                    Button("Refresh Herds", systemImage: "arrow.clockwise") {
                        refresh()
                    }
                    .disabled(isBusy)
                }

                Section("Create Herd") {
                    TextField("Herd name", text: $newHerdName)
                        .disabled(isBusy)
                    Button("Create Herd") {
                        Task { @MainActor in await create() }
                    }
                    .disabled(isBusy || newHerdName.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty)
                    Text("Creating a Herd is an explicit action. An empty list does not mean iCloud is empty.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Join Herd") {
                    Text("An invitation is required to join another owner's Herd. Invitation acceptance is not yet implemented.")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section("Herd Unavailable") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Choose Herd")
            .refreshable { refresh() }
            .task {
                refresh()
                // Poll the retained stores for roots imported after launch.
                // Stage 4 will provide remote-event-based invalidation.
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(3))
                    } catch {
                        break
                    }
                    guard !isBusy else { continue }
                    refresh()
                }
            }
        }
    }

    private func refresh() {
        do {
            herds = try directory.fetchHerds()
            errorMessage = nil
        } catch {
            // Preserve the last known complete list if a refresh fails.
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ herdID: UUID) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await selectHerd(herdID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func create() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let created = try await directory.createHerd(named: newHerdName)
            newHerdName = ""
            refresh()
            try await selectHerd(created.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif

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
