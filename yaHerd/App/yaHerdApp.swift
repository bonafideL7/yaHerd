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
    @State private var isConfirmingInitialICloud = false
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
                    } actions: {
                        #if DEBUG
                        Button("Use Local Storage Next Launch") {
                            disableDevelopmentICloud()
                        }
                        #endif
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
                        Button("Use Local Storage Next Launch") {
                            disableDevelopmentICloud()
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

                case .developmentModeSelection:
                    ContentUnavailableView {
                        Label("Choose Simulator Storage", systemImage: "externaldrive")
                    } description: {
                        Text("This simulator has no Herd database. Choose iCloud to import " +
                             "your existing Herd without creating an unrelated local Herd. " +
                             "Local mode creates a separate Herd on this device.")
                    } actions: {
                        Button("Use iCloud Development") {
                            isConfirmingInitialICloud = true
                        }
                        Button("Create Local Herd") {
                            Task { @MainActor in await chooseInitialStorageMode(enableICloud: false) }
                        }
                    }
                    .confirmationDialog(
                        "Import Existing iCloud Herd?",
                        isPresented: $isConfirmingInitialICloud
                    ) {
                        Button("Enable iCloud Development") {
                            Task { @MainActor in await chooseInitialStorageMode(enableICloud: true) }
                        }
                    } message: {
                        Text("Only enable after validating the signed development CloudKit " +
                             "schema. Existing Herd data may be uploaded to the development " +
                             "iCloud account. No replacement Herd will be created while importing.")
                    }

                case .developmentRestartRequired:
                    ContentUnavailableView {
                        Label("Restart yaHerd", systemImage: "arrow.clockwise")
                    } description: {
                        Text("iCloud development is disabled for the next launch. Stop and " +
                             "relaunch yaHerd from Xcode to use local storage. Your Herd " +
                             "records were not deleted.")
                    }
                #endif
                }
            }
            .task {
                guard !bootstrapStarted else { return }
                bootstrapStarted = true
                #if DEBUG
                do {
                    let url = try CoreDataPersistentContainer.defaultStoreURL()
                    let sharedURL = url.deletingLastPathComponent()
                        .appendingPathComponent(CoreDataPersistentContainer.sharedStoreFileName)
                    if CloudKitDevelopmentLaunch.requiresInitialChoice(
                        privateStoreExists: FileManager.default.fileExists(atPath: url.path),
                        sharedStoreExists: FileManager.default.fileExists(atPath: sharedURL.path),
                        enabled: applicationSettings.developmentICloudSyncEnabled
                    ) {
                        bootstrapState = .developmentModeSelection
                        return
                    }
                } catch {
                    // The normal bootstrap reports storage failures and recovery.
                }
                #endif
                bootstrapState = await Self.bootstrap()
            }
        }
    }

    #if DEBUG
    @MainActor
    private func chooseInitialStorageMode(enableICloud: Bool) async {
        applicationSettings.developmentICloudSyncEnabled = enableICloud
        bootstrapState = await Self.bootstrap()
    }

    @MainActor
    private func disableDevelopmentICloud() {
        applicationSettings.developmentICloudSyncEnabled = false
        // The existing CloudKit store assembly must be released before a
        // later local-only launch, so never open another store in this process.
        bootstrapState = .developmentRestartRequired
    }
    #endif

    @MainActor
    private static func bootstrap() async -> AppBootstrapState {
        #if DEBUG
        let developmentMirroringRequested =
            UserDefaults.standard.bool(forKey: CloudKitDevelopmentLaunch.settingsKey)
        #endif
        do {
            let storeURL = try CoreDataPersistentContainer.defaultStoreURL()
            let persistence: CoreDataAppPersistenceAssembly
            let storageMode: AppLaunchStorageMode
            #if DEBUG
            // Stage 2 explicitly opted-in device testing. The active mode
            // is visible in Settings; disabled always uses the local loader.
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
            #if DEBUG
            // An incomplete import or invalid developer activation is not
            // a SQLite load failure. Do not create a placeholder recovery Herd.
            if developmentMirroringRequested,
               let message = CloudKitDevelopmentLaunch.nonStorageStartupMessage(for: error) {
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
    case developmentImportPending(CloudKitDevelopmentPendingImport)
    case developmentModeSelection
    case developmentRestartRequired
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
/// Explicit, device-local development opt-in. The setting is configured
/// in yaHerd Settings, not an invisible Xcode Run environment variable.
/// The user must validate the development CloudKit schema before enabling it.
/// Release builds remain local until CloudKit's release acceptance criteria pass.
enum CloudKitDevelopmentLaunch: Equatable {
    case disabled
    case mirrored(selectedHerdID: UUID?)

    static let settingsKey = ApplicationSettingKey.developmentICloudSyncEnabled.rawValue

    static func requiresInitialChoice(
        privateStoreExists: Bool,
        sharedStoreExists: Bool,
        enabled: Bool
    ) -> Bool {
        !privateStoreExists && !sharedStoreExists && !enabled
    }

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
