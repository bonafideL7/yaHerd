import Foundation
import UIKit

/// Production Core Data-only application graph. The startup loader supplies one
/// durable or in-memory assembly and resolves its Herd before creating feature ports.
/// No feature in this graph depends on SwiftData or on another persistence stack.
@MainActor
final class CoreDataAppPersistenceAssembly: PersistenceAssembly {
    private let assembly: CoreDataPersistenceAssembly
    private let selection: AppCurrentHerdSelection

    var currentHerdSelection: AppCurrentHerdSelection { selection }

    func selectedHerdAuthorization(recordIdentity: URL? = nil) -> HerdAuthorization {
        assembly.contextFactory.authorization(for: selection.snapshot, recordIdentity: recordIdentity)
    }
    var herdImportState: HerdImportState { assembly.contextFactory.herdImportState }
    var storageActivity: StorageActivitySnapshot { assembly.contextFactory.storageActivity }

    private init(
        assembly: CoreDataPersistenceAssembly,
        selection: AppCurrentHerdSelection
    ) {
        self.assembly = assembly
        self.selection = selection
    }

    convenience init(
        assembly: CoreDataPersistenceAssembly,
        currentHerdID: UUID?
    ) {
        self.init(
            assembly: assembly,
            selection: AppCurrentHerdSelection(currentHerdID: currentHerdID)
        )
    }

    /// Store opening and Herd discovery are distinct: an inventory failure
    /// must not discard successfully loaded stores or create a substitute root.
    static func load(
        at storeURL: URL,
        selectionPreferences: UserDefaults = .standard
    ) async throws -> CoreDataAppPersistenceAssembly {
        let assembly = try await CoreDataPersistenceAssembly.load(storeURL: storeURL)
        return resolveHerdForChoice(using: assembly, selectionPreferences: selectionPreferences)
    }

    static func resolveHerdForChoice(
        using assembly: CoreDataPersistenceAssembly,
        requestedHerdID: UUID? = nil,
        selectionPreferences: UserDefaults = .standard
    ) -> CoreDataAppPersistenceAssembly {
        let selection = AppCurrentHerdSelection(defaults: selectionPreferences)
        let repository = CoreDataHerdRepository(selection: selection, assembly: assembly)
        do {
            let inventory = try repository.fetchHerdInventory()
            if let requestedHerdID {
                try selection.selectAccessibleHerd(
                    requestedHerdID, from: inventory.herds, remember: false
                )
            } else {
                // Never auto-pick the first imported root just because other
                // owned/shared roots have not arrived yet.
                let importState = assembly.contextFactory.herdImportState
                selection.restoreAccessibleHerd(
                    from: inventory.herds,
                    allowAutomaticChoice: !inventory.hasIncompleteRoots &&
                        inventory.ambiguousHerdIDs.isEmpty &&
                        (importState == .localOnly || importState == .complete)
                )
            }
        } catch {
            // Keep the original stores active; the chooser re-reads inventory
            // and reports the error. No automatic Herd creation occurs.
        }
        return CoreDataAppPersistenceAssembly(assembly: assembly, selection: selection)
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

    /// Probe the chosen Herd through the same loaded stores without changing
    /// the active Herd or writing a selected-Herd preference.
    func makeReadinessCandidate(for herd: AccessibleHerd) throws -> CoreDataAppPersistenceAssembly {
        let candidate = AppCurrentHerdSelection()
        try candidate.selectAccessibleHerd(herd.id, from: [herd], remember: false)
        return CoreDataAppPersistenceAssembly(assembly: assembly, selection: candidate)
    }

    /// Platform sharing preparation is explicitly scoped to the selected
    /// store-qualified root. No CKShare or Core Data object enters the feature
    /// dependency graph; the native presentation adapter will use this later.
    func verifySelectedHerdGraph() async throws -> HerdGraphVerification {
        let snapshot = selection.snapshot
        let result = try await assembly.contextFactory.verifyHerdGraph(for: snapshot)
        guard selection.snapshot == snapshot else { throw CancellationError() }
        return result
    }

    func discoverSelectedHerdShare() async throws -> HerdShareDiscovery {
        let snapshot = selection.snapshot
        let result = try await assembly.contextFactory.discoverOwnedShare(for: snapshot)
        guard selection.snapshot == snapshot else {
            throw CoreDataHerdSharingError.selectionChanged
        }
        return result
    }

    func prepareSelectedHerdShare() async throws -> HerdShareDiscovery {
        let snapshot = selection.snapshot
        let result = try await assembly.contextFactory.prepareOwnedShare(for: snapshot)
        guard selection.snapshot == snapshot else {
            throw CoreDataHerdSharingError.selectionChanged
        }
        return result
    }

    func prepareSharingInterface(
        onChange: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable () -> Void
    ) async throws -> UIViewController {
        let snapshot = selection.snapshot
        guard let rootIdentity = snapshot.rootIdentity else {
            throw HerdRepositoryError.missingHerd
        }
        let result = try await prepareSelectedHerdShare()
        guard selection.snapshot == snapshot else {
            throw CoreDataHerdSharingError.selectionChanged
        }
        guard case .existing(membership: .complete) = result else {
            throw CoreDataHerdSharingError.incompleteMembership
        }
        try Task.checkCancellation()
        return try assembly.contextFactory.makeOwnedSharingController(
            rootIdentity: rootIdentity, onChange: onChange, onFailure: onFailure
        )
    }

    func acceptHerdInvitation(_ invitation: HerdInvitation) async throws {
        try await assembly.contextFactory.acceptHerdInvitation(invitation)
    }

    func importedInvitationRoots(identities: Set<String>, roots: [URL]) throws -> Set<String> {
        try assembly.contextFactory.importedInvitationRoots(identities: identities, roots: roots)
    }

    func stopSelectedHerdSharing(expectedRoot: URL) async throws {
        guard selection.selectedRootIdentity == expectedRoot else {
            throw CoreDataHerdSharingError.selectionChanged
        }
        try await assembly.contextFactory.stopOwnedSharing(rootIdentity: expectedRoot)
    }

    func leaveSelectedHerd() async throws {
        let snapshot = selection.snapshot
        guard let root = snapshot.rootIdentity, snapshot.id != nil else {
            throw HerdRepositoryError.missingHerd
        }
        try await assembly.contextFactory.leaveJoinedHerd(rootIdentity: root)
        // Match the actual departed root, including an A → B → A selection
        // change during the network request. Do not deactivate another root.
        if selection.selectedRootIdentity == root {
            selection.deferCurrentHerdUntilImportReady()
        }
    }

    func makeRemoteHistoryCoordinator(
        mutationCenter: ApplicationMutationCenter,
        herdDirectory: HerdDirectoryController
    ) -> AppRemoteHistoryCoordinator? {
        guard let wakeups = assembly.contextFactory.historyWakeups else { return nil }
        return AppRemoteHistoryCoordinator(
            contextFactory: assembly.contextFactory,
            wakeups: wakeups,
            mutationCenter: mutationCenter,
            herdDirectory: herdDirectory
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
        let selectedHerd: @MainActor @Sendable () -> HerdSelectionSnapshot = {
            selectedHerdSelection.snapshot
        }
        let dashboardQueryReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            currentSelection: selectedHerd
        )
        let homeFieldCheckQueryReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            currentSelection: selectedHerd
        )
        let homeWorkingQueryReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            currentSelection: selectedHerd
        )
        let animalListQueryReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            currentSelection: selectedHerd
        )
        let parentOptionQueryReader = CoreDataReadModelActor(
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            currentSelection: selectedHerd
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
