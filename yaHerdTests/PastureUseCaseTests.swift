import XCTest
@testable import yaHerd

@MainActor
final class PastureUseCaseTests: XCTestCase {
    func testCreatePastureNormalizesInputBeforeCreate() throws {
        let repository = PastureCreateRepositorySpy()
        let useCase = CreatePastureUseCase(repository: repository)

        _ = try useCase.execute(
            input: PastureInput(name: "  North  ", acreage: 10, usableAcreage: 8, targetAcresPerHead: 2)
        )

        XCTAssertEqual(repository.createdInputs, [PastureInput(name: "North", acreage: 10, usableAcreage: 8, targetAcresPerHead: 2)])
    }

    func testCreatePastureRejectsDuplicateNameBeforeCreate() {
        let repository = PastureCreateRepositorySpy()
        repository.duplicateNames = ["north"]
        let useCase = CreatePastureUseCase(repository: repository)

        XCTAssertThrowsError(
            try useCase.execute(input: PastureInput(name: "North", acreage: nil, usableAcreage: nil, targetAcresPerHead: nil))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .duplicateName("North"))
        }
        XCTAssertTrue(repository.createdInputs.isEmpty)
    }

    func testUpdatePasturePassesCurrentPastureIDToDuplicateCheck() throws {
        let repository = PastureUpdateRepositorySpy()
        let pastureID = UUID()
        let useCase = UpdatePastureUseCase(repository: repository)

        _ = try useCase.execute(
            id: pastureID,
            input: PastureInput(name: " South ", acreage: nil, usableAcreage: nil, targetAcresPerHead: nil)
        )

        XCTAssertEqual(repository.receivedExcludingIDs, [pastureID])
        XCTAssertEqual(repository.updatedIDs, [pastureID])
        XCTAssertEqual(repository.updatedInputs, [PastureInput(name: "South", acreage: nil, usableAcreage: nil, targetAcresPerHead: nil)])
    }

    func testCreatePastureGroupNormalizesAndPersistsValidInput() throws {
        let repository = PastureGroupRepositorySpy()
        let useCase = CreatePastureGroupUseCase(repository: repository)

        _ = try useCase.execute(name: "  Spring  ", grazeDays: 7, restDays: 21)

        XCTAssertEqual(repository.createdInputs, [PastureGroupInput(name: "Spring", grazeDays: 7, restDays: 21)])
    }

    func testUpdatePastureGroupPassesCurrentGroupIDToDuplicateCheck() throws {
        let repository = PastureGroupRepositorySpy()
        let groupID = UUID()
        let useCase = UpdatePastureGroupUseCase(repository: repository)

        _ = try useCase.execute(id: groupID, name: " Summer ", grazeDays: 10, restDays: 30)

        XCTAssertEqual(repository.receivedExcludingIDs, [groupID])
        XCTAssertEqual(repository.updatedIDs, [groupID])
        XCTAssertEqual(repository.updatedInputs, [PastureGroupInput(name: "Summer", grazeDays: 10, restDays: 30)])
    }

    func testReorderPasturesRejectsDuplicateIDsBeforeRepositoryCall() {
        let repository = PastureOrderingSpy()
        let pastureID = UUID()
        let useCase = ReorderPasturesUseCase(repository: repository)

        XCTAssertThrowsError(try useCase.execute(ids: [pastureID, pastureID])) { error in
            XCTAssertEqual(error as? PastureRepositoryError, .duplicatePastureIDs)
        }
        XCTAssertTrue(repository.reorderedIDs.isEmpty)
    }

    func testAtomicPastureDeleteBuildsOneOrderedPlanAndPublishesAfterCommit() async throws {
        let first = UUID()
        let empty = UUID()
        let animalA = UUID()
        let animalB = UUID()
        let archivedAt = Date(timeIntervalSinceReferenceDate: 740_000)

        let reader = PastureDeleteRepositorySpy()
        reader.existingIDs = [first, empty]
        reader.residentAnimalsByPastureID[first] = [
            PastureTestSupport.makeAnimalSummary(id: animalB),
            PastureTestSupport.makeAnimalSummary(id: animalA)
        ]
        let writer = AtomicPastureDeletionWriterSpy()
        let center = ApplicationMutationCenter()
        let command = MutationPublishingPastureDeletionCommand(
            base: DeletePasturesAtomicallyUseCase(
                pastureReader: reader,
                transactionWriter: writer
            ),
            mutationRecorder: ApplicationMutationPipeline(center: center),
            writePolicy: LocalDataWritePolicy(dataAccessMode: .readWrite)
        )

        try await command.deletePastures(ids: [first, empty], archivedAt: archivedAt)

        XCTAssertEqual(reader.validateCalls, [[first, empty]])
        XCTAssertEqual(reader.fetchedResidentPastureIDs, [first, empty])
        XCTAssertTrue(reader.deletedIDs.isEmpty, "The atomic writer alone must delete Pastures.")
        XCTAssertEqual(writer.plans.count, 1)

        let plan = try XCTUnwrap(writer.plans.first)
        XCTAssertEqual(
            plan.expectedStates,
            [
                PastureDeletionExpectedState(
                    pastureID: first,
                    residentAnimalIDs: Set([animalA, animalB])
                ),
                PastureDeletionExpectedState(
                    pastureID: empty,
                    residentAnimalIDs: []
                )
            ]
        )
        XCTAssertEqual(
            plan.operations,
            [
                .moveAnimals(
                    animalIDs: [animalA, animalB].sorted {
                        $0.uuidString < $1.uuidString
                    },
                    fromPastureID: first,
                    toPastureID: nil
                ),
                .archiveFieldChecks(pastureIDs: [first, empty], archivedAt: archivedAt),
                .deletePastures(ids: [first, empty])
            ]
        )
        XCTAssertEqual(center.currentSequence, 1)
        XCTAssertEqual(center.pastureRevision, 1)
        XCTAssertEqual(center.homeRevision, 1)
        XCTAssertEqual(center.animalRevision, 1)
        XCTAssertEqual(center.fieldCheckRevision, 1)
    }

    func testAtomicPastureDeleteRejectsInvalidInputAndFailedWritesWithoutPublication() async {
        let pastureID = UUID()
        let missingID = UUID()
        let reader = PastureDeleteRepositorySpy()
        reader.existingIDs = [pastureID]
        let writer = AtomicPastureDeletionWriterSpy()
        let center = ApplicationMutationCenter()
        let command = MutationPublishingPastureDeletionCommand(
            base: DeletePasturesAtomicallyUseCase(
                pastureReader: reader,
                transactionWriter: writer
            ),
            mutationRecorder: ApplicationMutationPipeline(center: center),
            writePolicy: LocalDataWritePolicy(dataAccessMode: .readWrite)
        )
        let date = Date(timeIntervalSinceReferenceDate: 740_001)

        try? await command.deletePastures(ids: [], archivedAt: date)
        XCTAssertTrue(reader.validateCalls.isEmpty)
        XCTAssertTrue(writer.plans.isEmpty)
        XCTAssertEqual(center.currentSequence, 0)

        do {
            try await command.deletePastures(ids: [pastureID, pastureID], archivedAt: date)
            XCTFail("Expected duplicate Pasture IDs to fail before any lookup.")
        } catch {
            XCTAssertEqual(error as? PastureRepositoryError, .duplicatePastureIDs)
        }
        XCTAssertTrue(reader.validateCalls.isEmpty)

        do {
            try await command.deletePastures(ids: [missingID], archivedAt: date)
            XCTFail("Expected a missing Pasture to fail before transaction submission.")
        } catch {
            XCTAssertEqual(
                error as? PastureRepositoryError,
                .pastureIDsNotFound([missingID])
            )
        }
        XCTAssertTrue(writer.plans.isEmpty)

        writer.errorToThrow = PastureTestError.forced
        do {
            try await command.deletePastures(ids: [pastureID], archivedAt: date)
            XCTFail("Expected the failed atomic write to propagate.")
        } catch {
            XCTAssertEqual(error as? PastureTestError, .forced)
        }
        XCTAssertEqual(writer.plans.count, 1)
        XCTAssertEqual(center.currentSequence, 0)

        let recovery = MutationPublishingPastureDeletionCommand(
            base: DeletePasturesAtomicallyUseCase(
                pastureReader: reader,
                transactionWriter: writer
            ),
            mutationRecorder: ApplicationMutationPipeline(center: center),
            writePolicy: LocalDataWritePolicy(dataAccessMode: .recoveryReadOnly)
        )
        do {
            try await recovery.deletePastures(ids: [pastureID], archivedAt: date)
            XCTFail("Expected recovery mode to reject the deletion.")
        } catch {
            XCTAssertTrue(error is LocalDataWritePolicy.WriteError)
        }
        XCTAssertEqual(writer.plans.count, 1)
        XCTAssertEqual(center.currentSequence, 0)
    }

    func testDeletePasturesCoordinatesAnimalUnassignmentFieldCheckArchiveAndPastureDelete() async throws {
        let pastureID = UUID()
        let animalID = UUID()
        let pastureRepository = PastureDeleteRepositorySpy()
        pastureRepository.existingIDs = [pastureID]
        pastureRepository.residentAnimalsByPastureID = [
            pastureID: [PastureTestSupport.makeAnimalSummary(id: animalID)]
        ]
        let animalRepository = AnimalPastureMovingSpy()
        let fieldCheckRepository = FieldCheckPastureArchiveWriterSpy()
        let useCase = DeletePasturesUseCase(
            pastureRepository: pastureRepository,
            animalRepository: animalRepository,
            fieldCheckRepository: fieldCheckRepository
        )

        try await useCase.execute(ids: [pastureID], archivedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(pastureRepository.validateCalls, [[pastureID]])
        XCTAssertEqual(pastureRepository.fetchedResidentPastureIDs, [pastureID])
        XCTAssertEqual(animalRepository.moveCalls.count, 1)
        XCTAssertEqual(animalRepository.moveCalls.first?.ids, [animalID])
        XCTAssertNil(animalRepository.moveCalls.first?.pastureID)
        XCTAssertEqual(fieldCheckRepository.archiveCalls.map(\.pastureIDs), [[pastureID]])
        XCTAssertEqual(fieldCheckRepository.archiveCalls.first?.archivedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(pastureRepository.deletedIDs, [[pastureID]])
    }

    func testDeletePasturesRejectsDuplicateIDsBeforeSideEffects() async {
        let pastureID = UUID()
        let pastureRepository = PastureDeleteRepositorySpy()
        pastureRepository.existingIDs = [pastureID]
        let animalRepository = AnimalPastureMovingSpy()
        let fieldCheckRepository = FieldCheckPastureArchiveWriterSpy()
        let useCase = DeletePasturesUseCase(
            pastureRepository: pastureRepository,
            animalRepository: animalRepository,
            fieldCheckRepository: fieldCheckRepository
        )

        do {
            try await useCase.execute(ids: [pastureID, pastureID])
            XCTFail("Expected duplicate pasture IDs to be rejected.")
        } catch {
            XCTAssertEqual(error as? PastureRepositoryError, .duplicatePastureIDs)
        }

        XCTAssertTrue(pastureRepository.validateCalls.isEmpty)
        XCTAssertTrue(animalRepository.moveCalls.isEmpty)
        XCTAssertTrue(fieldCheckRepository.archiveCalls.isEmpty)
        XCTAssertTrue(pastureRepository.deletedIDs.isEmpty)
    }

    func testDeletePasturesDoesNotMoveAnimalsWhenThereAreNoResidents() async throws {
        let pastureID = UUID()
        let pastureRepository = PastureDeleteRepositorySpy()
        pastureRepository.existingIDs = [pastureID]
        let animalRepository = AnimalPastureMovingSpy()
        let fieldCheckRepository = FieldCheckPastureArchiveWriterSpy()
        let useCase = DeletePasturesUseCase(
            pastureRepository: pastureRepository,
            animalRepository: animalRepository,
            fieldCheckRepository: fieldCheckRepository
        )

        try await useCase.execute(ids: [pastureID])

        XCTAssertTrue(animalRepository.moveCalls.isEmpty)
        XCTAssertEqual(fieldCheckRepository.archiveCalls.map(\.pastureIDs), [[pastureID]])
        XCTAssertEqual(pastureRepository.deletedIDs, [[pastureID]])
    }
    func testDeletePastureGroupsValidatesBeforeDelete() throws {
        let groupID = UUID()
        let repository = PastureGroupDeleteRepositorySpy()
        repository.existingIDs = [groupID]
        let useCase = DeletePastureGroupsUseCase(repository: repository)

        try useCase.execute(ids: [groupID])

        XCTAssertEqual(repository.validateCalls, [[groupID]])
        XCTAssertEqual(repository.deletedIDs, [[groupID]])
    }

    func testDeletePastureGroupsRejectsMissingIDBeforeDelete() {
        let groupID = UUID()
        let repository = PastureGroupDeleteRepositorySpy()
        let useCase = DeletePastureGroupsUseCase(repository: repository)

        XCTAssertThrowsError(try useCase.execute(ids: [groupID])) { error in
            XCTAssertEqual(error as? PastureRepositoryError, .pastureGroupIDsNotFound([groupID]))
        }

        XCTAssertTrue(repository.deletedIDs.isEmpty)
    }

    func testAssignPastureToGroupValidatesPastureAndGroupBeforeAssignment() throws {
        let pastureID = UUID()
        let groupID = UUID()
        let repository = PastureGroupAssignRepositorySpy()
        repository.existingPastureIDs = [pastureID]
        repository.existingGroupIDs = [groupID]
        let useCase = AssignPastureToGroupUseCase(repository: repository)

        try useCase.execute(pastureID: pastureID, groupID: groupID)

        XCTAssertEqual(repository.validatedPastureIDs, [[pastureID]])
        XCTAssertEqual(repository.validatedGroupIDs, [[groupID]])
        XCTAssertEqual(repository.assignmentCalls.count, 1)
        XCTAssertEqual(repository.assignmentCalls.first?.pastureID, pastureID)
        XCTAssertEqual(repository.assignmentCalls.first?.groupID, groupID)
    }

    func testAssignPastureToNilGroupDoesNotValidateGroupID() throws {
        let pastureID = UUID()
        let repository = PastureGroupAssignRepositorySpy()
        repository.existingPastureIDs = [pastureID]
        let useCase = AssignPastureToGroupUseCase(repository: repository)

        try useCase.execute(pastureID: pastureID, groupID: nil)

        XCTAssertEqual(repository.validatedPastureIDs, [[pastureID]])
        XCTAssertTrue(repository.validatedGroupIDs.isEmpty)
        XCTAssertEqual(repository.assignmentCalls.count, 1)
        XCTAssertEqual(repository.assignmentCalls.first?.pastureID, pastureID)
        XCTAssertNil(repository.assignmentCalls.first?.groupID)
    }

}

@MainActor
private final class AtomicPastureDeletionWriterSpy: PastureDeletionTransactionWriting {
    private(set) var plans: [DeletePasturesTransactionPlan] = []
    var errorToThrow: Error?

    func deletePastures(_ plan: DeletePasturesTransactionPlan) async throws {
        plans.append(plan)
        if let errorToThrow { throw errorToThrow }
    }
}
