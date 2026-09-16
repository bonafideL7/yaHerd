//
//  yaHerdApp.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//

import SwiftData
import SwiftUI

@main
struct yaHerdApp: App {
    private let bootstrapState: AppBootstrapState
    private let applicationSettings: ApplicationSettings

    init() {
        let applicationSettings = ApplicationSettings()
        self.applicationSettings = applicationSettings
        self.bootstrapState = Self.bootstrap()
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrapState {
            case .ready(let runtime):
                RunningAppView(
                    runtime: runtime,
                    applicationSettings: applicationSettings
                )

            case .storageUnavailable(let message):
                StartupStorageFailureView(message: message)
            }
        }
    }

    private static func bootstrap() -> AppBootstrapState {
        do {
            let container = try ModelContainerFactory.makeContainer()
            try Self.runStartupDataMigrations(in: container.mainContext)

            AppLaunchDiagnostics.record(actualStorageMode: .local)

            let persistence = Self.makePersistenceRuntime(
                modelContainer: container
            )

            return .ready(
                AppRuntime(
                    persistenceLifetime: persistence.assembly,
                    dependencies: persistence.dependencies,
                    dataAccessMode: .readWrite,
                    recoveryContext: nil,
                    storageError: nil
                )
            )
        } catch {
            let primaryError = error

            do {
                let fallbackContainer = try ModelContainerFactory.makeRecoveryContainer()

                let startupMessage = """
                Persistent storage could not be opened. yaHerd is running in recovery mode, and changes from this session will not be saved. Original error: \(primaryError.localizedDescription)
                """

                AppLaunchDiagnostics.record(
                    actualStorageMode: .recovery,
                    startupError: startupMessage
                )

                let persistence = Self.makePersistenceRuntime(
                    modelContainer: fallbackContainer,
                    dataAccessMode: .recoveryReadOnly
                )
                return .ready(
                    AppRuntime(
                        persistenceLifetime: persistence.assembly,
                        dependencies: persistence.dependencies,
                        dataAccessMode: .recoveryReadOnly,
                        recoveryContext: RecoveryModeContext(
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
                    actualStorageMode: .unavailable,
                    startupError: startupMessage
                )

                return .storageUnavailable(startupMessage)
            }
        }
    }

    private static func makePersistenceRuntime(
        modelContainer: ModelContainer,
        dataAccessMode: AppDataAccessMode = .readWrite
    ) -> AppPersistenceRuntime {
        let persistenceAssembly: any PersistenceAssembly = SwiftDataPersistenceAssembly(
            modelContainer: modelContainer
        )
        let dependencies = persistenceAssembly.makeDependencies(
            dataAccessMode: dataAccessMode
        )
        return AppPersistenceRuntime(
            assembly: persistenceAssembly,
            dependencies: dependencies
        )
    }

    private static func runStartupDataMigrations(in context: ModelContext) throws {
        try DefaultHerdBootstrapper.ensureDefaultHerdForAppLaunch(in: context)
        try FieldCheckHistoricalSnapshotMigrator.runIfNeeded(in: context)

        try SwiftDataTagColorRepository(
            context: context,
            duplicateResolutionPolicy: .stableSortOrderWins
        ).prepareLibraryForWritableUse()
    }

    static func makeSchema() -> Schema {
        ModelContainerFactory.schema
    }
}

private enum AppBootstrapState {
    case ready(AppRuntime)
    case storageUnavailable(String)
}

private struct AppPersistenceRuntime {
    let assembly: any PersistenceAssembly
    let dependencies: AppDependencies
}

private struct AppRuntime {
    // Retain the selected persistence implementation for the lifetime of the running app without
    // exposing its concrete container to SwiftUI or Presentation.
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
            .onChange(of: navigationMutationRevision) { _, _ in
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
