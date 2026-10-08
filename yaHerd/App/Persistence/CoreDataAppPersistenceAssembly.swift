import Foundation

/// Prepared Core Data-only application graph. The final M10 startup switch supplies
/// a loaded CoreDataPersistenceAssembly and a durable, bootstrapped Herd UUID.
/// No feature in this graph depends on SwiftData or on a separate persistence stack.
@MainActor
final class CoreDataAppPersistenceAssembly: PersistenceAssembly {
    private let assembly: CoreDataPersistenceAssembly
    private let selection: AppCurrentHerdSelection

    init(assembly: CoreDataPersistenceAssembly, currentHerdID: UUID) {
        self.assembly = assembly
        self.selection = AppCurrentHerdSelection(currentHerdID: currentHerdID)
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
            assembly: assembly,
            currentHerdID: selectedHerdID
        )
        let homeFieldCheckQueryReader = CoreDataReadModelActor(
            assembly: assembly,
            currentHerdID: selectedHerdID
        )
        let homeWorkingQueryReader = CoreDataReadModelActor(
            assembly: assembly,
            currentHerdID: selectedHerdID
        )
        let animalListQueryReader = CoreDataReadModelActor(
            assembly: assembly,
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
                editorRepository: animalRepository,
                detailRepository: animalRepository,
                timelineReader: animalRepository,
                parentOptionReader: animalRepository,
                healthRecordAdder: animalRepository,
                pregnancyCheckAdder: animalRepository,
                pastureReferenceReader: pastureRepository,
                sampleDataSeeder: nil,
                mutationStream: mutationCenter
            ),
            pastureFeatureDependencies: PastureFeatureDependencies(
                listRepository: pastureRepository,
                createRepository: pastureRepository,
                detailRepository: pastureRepository,
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
                pastureReferenceReader: pastureRepository,
                mutationStream: mutationCenter
            ),
            workingSessionFeatureDependencies: WorkingSessionFeatureDependencies(
                repository: workingRepository,
                animalSummaryReader: animalRepository,
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
