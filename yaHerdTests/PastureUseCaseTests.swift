import XCTest
@testable import yaHerd

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

    func testDeletePasturesCoordinatesAnimalUnassignmentFieldCheckCleanupAndPastureDelete() throws {
        let pastureID = UUID()
        let animalID = UUID()
        let pastureRepository = PastureDeleteRepositorySpy()
        pastureRepository.existingIDs = [pastureID]
        pastureRepository.residentAnimalsByPastureID = [
            pastureID: [PastureTestSupport.makeAnimalSummary(id: animalID)]
        ]
        let animalRepository = AnimalPastureMovingSpy()
        let fieldCheckRepository = FieldCheckPastureCleanupWriterSpy()
        let useCase = DeletePasturesUseCase(
            pastureRepository: pastureRepository,
            animalRepository: animalRepository,
            fieldCheckRepository: fieldCheckRepository
        )

        try useCase.execute(ids: [pastureID])

        XCTAssertEqual(pastureRepository.validateCalls, [[pastureID]])
        XCTAssertEqual(pastureRepository.fetchedResidentPastureIDs, [pastureID])
        XCTAssertEqual(animalRepository.moveCalls.count, 1)
        XCTAssertEqual(animalRepository.moveCalls.first?.ids, [animalID])
        XCTAssertNil(animalRepository.moveCalls.first?.pastureID)
        XCTAssertEqual(fieldCheckRepository.cleanupCalls, [[pastureID]])
        XCTAssertEqual(pastureRepository.deletedIDs, [[pastureID]])
    }

    func testDeletePasturesRejectsDuplicateIDsBeforeSideEffects() {
        let pastureID = UUID()
        let pastureRepository = PastureDeleteRepositorySpy()
        pastureRepository.existingIDs = [pastureID]
        let animalRepository = AnimalPastureMovingSpy()
        let fieldCheckRepository = FieldCheckPastureCleanupWriterSpy()
        let useCase = DeletePasturesUseCase(
            pastureRepository: pastureRepository,
            animalRepository: animalRepository,
            fieldCheckRepository: fieldCheckRepository
        )

        XCTAssertThrowsError(try useCase.execute(ids: [pastureID, pastureID])) { error in
            XCTAssertEqual(error as? PastureRepositoryError, .duplicatePastureIDs)
        }

        XCTAssertTrue(pastureRepository.validateCalls.isEmpty)
        XCTAssertTrue(animalRepository.moveCalls.isEmpty)
        XCTAssertTrue(fieldCheckRepository.cleanupCalls.isEmpty)
        XCTAssertTrue(pastureRepository.deletedIDs.isEmpty)
    }

    func testDeletePasturesDoesNotMoveAnimalsWhenThereAreNoResidents() throws {
        let pastureID = UUID()
        let pastureRepository = PastureDeleteRepositorySpy()
        pastureRepository.existingIDs = [pastureID]
        let animalRepository = AnimalPastureMovingSpy()
        let fieldCheckRepository = FieldCheckPastureCleanupWriterSpy()
        let useCase = DeletePasturesUseCase(
            pastureRepository: pastureRepository,
            animalRepository: animalRepository,
            fieldCheckRepository: fieldCheckRepository
        )

        try useCase.execute(ids: [pastureID])

        XCTAssertTrue(animalRepository.moveCalls.isEmpty)
        XCTAssertEqual(fieldCheckRepository.cleanupCalls, [[pastureID]])
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
