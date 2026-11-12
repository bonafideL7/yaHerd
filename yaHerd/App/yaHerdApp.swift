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
        let developmentMirroringRequested =
            ProcessInfo.processInfo.environment["YAHERD_CLOUDKIT_DEV_MIRRORING"] == "1"
        #endif
        do {
            let storeURL = try CoreDataPersistentContainer.defaultStoreURL()
            let persistence: CoreDataAppPersistenceAssembly
            let storageMode: AppLaunchStorageMode
            #if DEBUG
            // Stage 2 physical-device acceptance only. Normal app launch is
            // local until signed schema validation and the full release gates.
            switch try CloudKitDevelopmentLaunch.resolve(
                environment: ProcessInfo.processInfo.environment
            ) {
            case .disabled:
                persistence = try await CoreDataAppPersistenceAssembly.load(
                    at: storeURL
                )
                storageMode = .local
            case .mirrored(let selectedHerdID):
                persistence = try await CoreDataAppPersistenceAssembly.loadCloudKit(
                    at: storeURL,
                    selectedHerdID: selectedHerdID,
                    mirroringEnabled: true
                )
                storageMode = .cloudKitDevelopment
            }
            #else
            persistence = try await CoreDataAppPersistenceAssembly.load(
                at: storeURL
            )
            storageMode = .local
            #endif
            let dependencies = persistence.makeDependencies(
                dataAccessMode: .readWrite
            )

            AppLaunchDiagnostics.record(actualStorageMode: storageMode)

            return .ready(
                AppRuntime(
                    persistenceLifetime: persistence,
                    dependencies: dependencies,
                    dataAccessMode: .readWrite,
                    recoveryContext: nil,
                    storageError: nil
                )
            )
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
}

private enum AppBootstrapState {
    case loading
    case ready(AppRuntime)
    case storageUnavailable(String)
    case developmentMirroringBlocked(String)
}

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
/// Deliberately opt-in developer path to exercise a real signed app graph
/// against private/shared CloudKit stores after M04 development schema checks.
/// This is not a release feature flag or proof that CloudKit has synchronized.
enum CloudKitDevelopmentLaunch: Equatable {
    case disabled
    case mirrored(selectedHerdID: UUID?)

    static func resolve(environment: [String: String]) throws -> Self {
        guard environment["YAHERD_CLOUDKIT_DEV_MIRRORING"] == "1" else {
            return .disabled
        }
        guard environment["YAHERD_CLOUDKIT_M04_VERIFIED"] == "1" else {
            throw CloudKitDevelopmentLaunchError.schemaDryRunRequired
        }
        if let rawHerdID = environment["YAHERD_CLOUDKIT_DEV_SELECTED_HERD_ID"] {
            guard let selectedHerdID = UUID(uuidString: rawHerdID) else {
                throw CloudKitDevelopmentLaunchError.invalidSelectedHerdID
            }
            return .mirrored(selectedHerdID: selectedHerdID)
        }
        return .mirrored(selectedHerdID: nil)
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
        return nil
    }
}

enum CloudKitDevelopmentLaunchError: LocalizedError, Equatable {
    case schemaDryRunRequired
    case invalidSelectedHerdID

    var errorDescription: String? {
        switch self {
        case .schemaDryRunRequired:
            return """
            Development iCloud mirroring is not enabled. First run and verify \
            the signed M04 schema dry-run, then set YAHERD_CLOUDKIT_M04_VERIFIED=1 \
            with YAHERD_CLOUDKIT_DEV_MIRRORING=1 in the development app scheme. \
            Mirroring can upload this device's Herd data to the development Apple Account.
            """
        case .invalidSelectedHerdID:
            return "YAHERD_CLOUDKIT_DEV_SELECTED_HERD_ID must be an existing Herd UUID. " +
                "Use it only with the signed development mirroring scheme to select a " +
                "specific owned or shared Herd. No Herd records were changed."
        }
    }
}
#endif
