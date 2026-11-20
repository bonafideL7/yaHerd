import Foundation

/// Production Core Data-only application graph. The startup loader supplies one
/// durable or in-memory assembly and resolves its Herd before creating feature ports.
/// No feature in this graph depends on SwiftData or on another persistence stack.
@MainActor
final class CoreDataAppPersistenceAssembly: PersistenceAssembly {
    private let assembly: CoreDataPersistenceAssembly
    private let selection: AppCurrentHerdSelection

    var currentHerdSelection: AppCurrentHerdSelection { selection }

    init(
        assembly: CoreDataPersistenceAssembly,
        currentHerdID: UUID?,
        selectionPreferences: UserDefaults? = nil
    ) {
        self.assembly = assembly
        self.selection = AppCurrentHerdSelection(
            currentHerdID: currentHerdID, defaults: selectionPreferences
        )
    }

    /// Production launch keeps one durable store and one selected Herd for all features.
    static func load(
        at storeURL: URL,
        selectionPreferences: UserDefaults = .standard
    ) async throws -> CoreDataAppPersistenceAssembly {
        let assembly = try await CoreDataPersistenceAssembly.load(storeURL: storeURL)
        let remembered = AppCurrentHerdSelection(defaults: selectionPreferences)
        let repository = CoreDataHerdRepository(selection: remembered, assembly: assembly)
        let available = try repository.fetchAccessibleHerds()
        remembered.restoreAccessibleHerd(from: available)

        let herdID: UUID?
        if let selected = remembered.currentHerdID {
            herdID = selected
        } else if available.isEmpty {
            // Only the strictly local first install creates the initial Herd.
            // A mirrored import always follows the separate choice path.
            herdID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
                assembly: assembly
            )
        } else {
            // A missing or invalid remembered ID is not permission to select
            // an arbitrary Herd, nor a storage failure.
            herdID = nil
        }

        return CoreDataAppPersistenceAssembly(
            assembly: assembly,
            currentHerdID: herdID,
            selectionPreferences: selectionPreferences
        )
    }

    /// Stage 2 application path. An explicit ID selects an existing private
    /// or shared Herd; otherwise use the one existing complete owned Herd.
    /// A mirrored store may still be importing: never create replacement
    /// Herd records or upload synthetic data during that interval.
    /// Normal startup remains local-only until signed schema validation
    /// and the Herd-selection lifecycle are ready.
    static func loadCloudKit(
        at storeURL: URL,
        selectedHerdID: UUID? = nil,
        mirroringEnabled: Bool
    ) async throws -> CoreDataAppPersistenceAssembly {
        let assembly = try await CoreDataPersistenceAssembly.loadCloudKit(
            storeURL: storeURL,
            mirroringEnabled: mirroringEnabled
        )
        return try resolveCloudKitHerd(
            using: assembly, privateStoreURL: storeURL, selectedHerdID: selectedHerdID
        )
    }

    /// Resolve a Herd against an already loaded dual-store assembly. Retaining
    /// this assembly while a newly installed device awaits CloudKit import
    /// keeps its mirroring engine alive; rechecking must never bootstrap a
    /// replacement Herd or reopen the persistent stores.
    static func resolveCloudKitHerd(
        using assembly: CoreDataPersistenceAssembly,
        privateStoreURL: URL,
        selectedHerdID: UUID? = nil,
        selectionPreferences: UserDefaults = .standard
    ) throws -> CoreDataAppPersistenceAssembly {
        // The selected UUID is a locally persisted preference, never proof of
        // CloudKit membership. Restore only IDs present in the loaded stores.
        // An empty import must not create a replacement Herd.
        let herdID: UUID
        if let selectedHerdID {
            herdID = selectedHerdID
        } else {
            let remembered = AppCurrentHerdSelection(defaults: selectionPreferences)
            let repository = CoreDataHerdRepository(selection: remembered, assembly: assembly)
            // This legacy CloudKit resolver defaults only to an owned/private Herd.
            // Shared Herds remain selectable through the explicit Stage 3 chooser.
            let owned = try repository.fetchAccessibleHerds().filter { $0.category == .owned }
            remembered.restoreAccessibleHerd(from: owned)
            if let selected = remembered.currentHerdID {
                herdID = selected
            } else if owned.isEmpty {
                throw HerdRepositoryError.missingHerd
            } else {
                throw CoreDataAppHerdBootstrapError.multipleLocalHerds(
                    count: owned.count
                )
            }
        }

        let context = assembly.contextFactory.makeReadContext()
        let lookup = assembly.lookup
        try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            // A CloudKit import can expose the root UUID before its required
            // fields. Defer the app graph rather than treating a partial Herd
            // as ready or creating a replacement starter Herd.
            _ = try herd.toSummary()
            guard try lookup.store(forHerdID: herdID, in: context) != nil else {
                throw HerdRepositoryError.missingHerd
            }
        }
        return CoreDataAppPersistenceAssembly(
            assembly: assembly,
            currentHerdID: herdID,
            selectionPreferences: selectionPreferences
        )
    }

    /// Stage 3 startup: enumerate owned and shared Herds without implicitly
    /// creating a local root. If no valid selection exists, retain the loaded
    /// stores and present the Herd chooser.
    /// An explicit developer-selected ID still uses strict Stage 2 validation.
    static func resolveCloudKitHerdForChoice(
        using assembly: CoreDataPersistenceAssembly,
        privateStoreURL: URL,
        requestedHerdID: UUID? = nil,
        selectionPreferences: UserDefaults = .standard
    ) throws -> CoreDataAppPersistenceAssembly {
        if let requestedHerdID {
            return try resolveCloudKitHerd(
                using: assembly,
                privateStoreURL: privateStoreURL,
                selectedHerdID: requestedHerdID,
                selectionPreferences: selectionPreferences
            )
        }
        let remembered = AppCurrentHerdSelection(defaults: selectionPreferences)
        let repository = CoreDataHerdRepository(selection: remembered, assembly: assembly)
        remembered.restoreAccessibleHerd(from: try repository.fetchAccessibleHerds())
        guard let selectedID = remembered.currentHerdID else {
            return CoreDataAppPersistenceAssembly(
                assembly: assembly, currentHerdID: nil,
                selectionPreferences: selectionPreferences
            )
        }
        return try resolveCloudKitHerd(
            using: assembly, privateStoreURL: privateStoreURL,
            selectedHerdID: selectedID, selectionPreferences: selectionPreferences
        )
    }

    /// A failed disk open must never trigger a SwiftData fallback or write to
    /// the failed store. Bootstrap this temporary Herd before enabling read-only
    /// application policy so all UI dependencies can still render safely.
    static func inMemoryRecovery() async throws -> CoreDataAppPersistenceAssembly {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let herdID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly
        )
        return CoreDataAppPersistenceAssembly(
            assembly: assembly,
            currentHerdID: herdID
        )
    }

    func makeDependencies(dataAccessMode: AppDataAccessMode) -> AppDependencies {
        let mutationCenter = ApplicationMutationCenter()
        let recorder = ApplicationMutationPipeline(center: mutationCenter)
        let writePolicy = LocalDataWritePolicy(dataAccessMode: dataAccessMode)

        let animalRepository = MutationPublishingAnimalRepository(
            base: CoreDataAnimalRepository(selection: selection, assembly: assembly),
            mutationRecorder: recorder,
            writePolicy: writePolicy
        )
        let pastureRepository = MutationPublishingCoreDataPastureRepository(
            base: CoreDataPastureRepository(selection: selection, assembly: assembly),
            mutationRecorder: recorder,
            writePolicy: writePolicy
        )
        let fieldCheckRepository = MutationPublishingFieldCheckRepository(
            base: CoreDataFieldCheckRepository(selection: selection, assembly: assembly),
            mutationRecorder: recorder,
            writePolicy: writePolicy
        )
        let workingRepository = MutationPublishingWorkingRepository(
            base: CoreDataWorkingAppRepository(selection: selection, assembly: assembly),
            mutationRecorder: recorder,
            writePolicy: writePolicy
        )
        let herdRepository = MutationPublishingHerdRepository(
            base: CoreDataHerdRepository(selection: selection, assembly: assembly),
            mutationRecorder: recorder,
            writePolicy: writePolicy
        )
        let tagColorRepository = MutationPublishingTagColorRepository(
            base: CoreDataTagColorRepository(selection: selection, assembly: assembly),
            mutationRecorder: recorder,
            writePolicy: writePolicy
        )

        let deletePastures = MutationPublishingPastureDeletionCommand(
            base: DeletePasturesAtomicallyUseCase(
                pastureReader: pastureRepository,
                transactionWriter: CoreDataPastureDeletionTransactionWriter(
                    selection: selection,
                    assembly: assembly
                )
            ),
            mutationRecorder: recorder,
            writePolicy: writePolicy
        )

        // Give each independently awaited production query its own actor/executor.
        // All actors resolve the same selected Herd and the same Core Data store.
        let selectedHerdSelection = selection
        let selectedHerdID: @MainActor @Sendable () -> UUID? = {
            selectedHerdSelection.currentHerdID
        }
        let dashboardQueryReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            currentHerdID: selectedHerdID
        )
        let homeFieldCheckQueryReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            currentHerdID: selectedHerdID
        )
        let homeWorkingQueryReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            currentHerdID: selectedHerdID
        )
        let animalListQueryReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            currentHerdID: selectedHerdID
        )
        let parentOptionQueryReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            currentHerdID: selectedHerdID
        )
        let animalListRepository = BackgroundQueryingAnimalListRepository(
            base: animalRepository,
            queryReader: animalListQueryReader
        )

        return AppDependencies(
            animalFeatureDependencies: AnimalFeatureDependencies(
                listRepository: animalListRepository,
                listQueryReader: animalListQueryReader,
                listSnapshotReader: animalListQueryReader,
                editorRepository: animalRepository,
                detailRepository: animalRepository,
                timelineReader: animalRepository,
                parentOptionReader: animalRepository,
                parentOptionQueryReader: parentOptionQueryReader,
                healthRecordAdder: animalRepository,
                pregnancyCheckAdder: animalRepository,
                pastureReferenceReader: pastureRepository,
                sampleDataSeeder: CoreDataSampleDataSeeder(
                    selection: selection,
                    assembly: assembly,
                    mutationRecorder: recorder,
                    writePolicy: writePolicy
                ),
                mutationStream: mutationCenter
            ),
            pastureFeatureDependencies: PastureFeatureDependencies(
                listRepository: pastureRepository,
                createRepository: pastureRepository,
                detailRepository: pastureRepository,
                existenceChecker: pastureRepository,
                groupListRepository: pastureRepository,
                groupDetailRepository: pastureRepository,
                groupEditorRepository: pastureRepository,
                referenceReader: pastureRepository,
                animalMover: animalRepository,
                fieldCheckArchiveWriter: fieldCheckRepository,
                deletionCommand: deletePastures,
                mutationStream: mutationCenter
            ),
            fieldCheckFeatureDependencies: FieldCheckFeatureDependencies(
                repository: fieldCheckRepository,
                animalRepository: animalRepository,
                animalReferenceQueryReader: animalListQueryReader,
                pastureReferenceReader: pastureRepository,
                mutationStream: mutationCenter
            ),
            workingSessionFeatureDependencies: WorkingSessionFeatureDependencies(
                repository: workingRepository,
                animalSummaryReader: animalRepository,
                animalReferenceQueryReader: animalListQueryReader,
                pastureReferenceReader: pastureRepository,
                mutationStream: mutationCenter
            ),
            homeFeatureDependencies: HomeFeatureDependencies(
                fieldCheckOverviewReader: fieldCheckRepository,
                dashboardQueryReader: dashboardQueryReader,
                homeFieldCheckQueryReader: homeFieldCheckQueryReader,
                homeWorkingQueryReader: homeWorkingQueryReader,
                mutationStream: mutationCenter
            ),
            tagColorRepository: tagColorRepository,
            herdRepository: herdRepository,
            applicationMutationCenter: mutationCenter
        )
    }
}
