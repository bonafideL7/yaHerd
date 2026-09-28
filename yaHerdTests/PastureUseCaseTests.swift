import XCTest
@testable import yaHerd

@MainActor
final class PastureUseCaseTests: XCTestCase {
    func testCreatePastureNormalizesInputBeforeCreate() async throws {
        let repository = PastureCreateRepositorySpy()
        let useCase = CreatePastureUseCase(repository: repository)

        _ = try await useCase.execute(
            input: PastureInput(name: "  North  ", acreage: 10, usableAcreage: 8, targetAcresPerHead: 2)
        )

        XCTAssertEqual(repository.createdInputs, [PastureInput(name: "North", acreage: 10, usableAcreage: 8, targetAcresPerHead: 2)])
    }

    func testCreatePastureRejectsDuplicateNameBeforeCreate() async {
        let repository = PastureCreateRepositorySpy()
        repository.duplicateNames = ["north"]
        let useCase = CreatePastureUseCase(repository: repository)

        await assertAsyncThrowsError(
            try await useCase.execute(input: PastureInput(name: "North", acreage: nil, usableAcreage: nil, targetAcresPerHead: nil))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .duplicateName("North"))
        }
        XCTAssertTrue(repository.createdInputs.isEmpty)
    }

    func testUpdatePasturePassesCurrentPastureIDToDuplicateCheck() async throws {
        let repository = PastureUpdateRepositorySpy()
        let pastureID = UUID()
        let useCase = UpdatePastureUseCase(repository: repository)

        _ = try await useCase.execute(
            id: pastureID,
            input: PastureInput(name: " South ", acreage: nil, usableAcreage: nil, targetAcresPerHead: nil)
        )

        XCTAssertEqual(repository.receivedExcludingIDs, [pastureID])
        XCTAssertEqual(repository.updatedIDs, [pastureID])
        XCTAssertEqual(repository.updatedInputs, [PastureInput(name: "South", acreage: nil, usableAcreage: nil, targetAcresPerHead: nil)])
    }

    func testCreatePastureGroupNormalizesAndPersistsValidInput() async throws {
        let repository = PastureGroupRepositorySpy()
        let useCase = CreatePastureGroupUseCase(repository: repository)

        _ = try await useCase.execute(name: "  Spring  ", grazeDays: 7, restDays: 21)

        XCTAssertEqual(repository.createdInputs, [PastureGroupInput(name: "Spring", grazeDays: 7, restDays: 21)])
    }

    func testUpdatePastureGroupPassesCurrentGroupIDToDuplicateCheck() async throws {
        let repository = PastureGroupRepositorySpy()
        let groupID = UUID()
        let useCase = UpdatePastureGroupUseCase(repository: repository)

        _ = try await useCase.execute(id: groupID, name: " Summer ", grazeDays: 10, restDays: 30)

        XCTAssertEqual(repository.receivedExcludingIDs, [groupID])
        XCTAssertEqual(repository.updatedIDs, [groupID])
        XCTAssertEqual(repository.updatedInputs, [PastureGroupInput(name: "Summer", grazeDays: 10, restDays: 30)])
    }

    func testReorderPasturesRejectsDuplicateIDsBeforeRepositoryCall() async {
        let repository = PastureOrderingSpy()
        let pastureID = UUID()
        let useCase = ReorderPasturesUseCase(repository: repository)

        await assertAsyncThrowsError(try await useCase.execute(ids: [pastureID, pastureID])) { error in
            XCTAssertEqual(error as? PastureRepositoryError, .duplicatePastureIDs)
        }
        XCTAssertTrue(repository.reorderedIDs.isEmpty)
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

        await assertAsyncThrowsError(try await useCase.execute(ids: [pastureID, pastureID])) { error in
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
    func testDeletePastureGroupsValidatesBeforeDelete() async throws {
        let groupID = UUID()
        let repository = PastureGroupDeleteRepositorySpy()
        repository.existingIDs = [groupID]
        let useCase = DeletePastureGroupsUseCase(repository: repository)

        try await useCase.execute(ids: [groupID])

        XCTAssertEqual(repository.validateCalls, [[groupID]])
        XCTAssertEqual(repository.deletedIDs, [[groupID]])
    }

    func testDeletePastureGroupsRejectsMissingIDBeforeDelete() async {
        let groupID = UUID()
        let repository = PastureGroupDeleteRepositorySpy()
        let useCase = DeletePastureGroupsUseCase(repository: repository)

        await assertAsyncThrowsError(try await useCase.execute(ids: [groupID])) { error in
            XCTAssertEqual(error as? PastureRepositoryError, .pastureGroupIDsNotFound([groupID]))
        }

        XCTAssertTrue(repository.deletedIDs.isEmpty)
    }

    func testAssignPastureToGroupValidatesPastureAndGroupBeforeAssignment() async throws {
        let pastureID = UUID()
        let groupID = UUID()
        let repository = PastureGroupAssignRepositorySpy()
        repository.existingPastureIDs = [pastureID]
        repository.existingGroupIDs = [groupID]
        let useCase = AssignPastureToGroupUseCase(repository: repository)

        try await useCase.execute(pastureID: pastureID, groupID: groupID)

        XCTAssertEqual(repository.validatedPastureIDs, [[pastureID]])
        XCTAssertEqual(repository.validatedGroupIDs, [[groupID]])
        XCTAssertEqual(repository.assignmentCalls.count, 1)
        XCTAssertEqual(repository.assignmentCalls.first?.pastureID, pastureID)
        XCTAssertEqual(repository.assignmentCalls.first?.groupID, groupID)
    }

    func testAssignPastureToNilGroupDoesNotValidateGroupID() async throws {
        let pastureID = UUID()
        let repository = PastureGroupAssignRepositorySpy()
        repository.existingPastureIDs = [pastureID]
        let useCase = AssignPastureToGroupUseCase(repository: repository)

        try await useCase.execute(pastureID: pastureID, groupID: nil)

        XCTAssertEqual(repository.validatedPastureIDs, [[pastureID]])
        XCTAssertTrue(repository.validatedGroupIDs.isEmpty)
        XCTAssertEqual(repository.assignmentCalls.count, 1)
        XCTAssertEqual(repository.assignmentCalls.first?.pastureID, pastureID)
        XCTAssertNil(repository.assignmentCalls.first?.groupID)
    }


    private func assertAsyncThrowsError<Value>(
        _ expression: @autoclosure () async throws -> Value,
        _ errorHandler: (Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected operation to throw.")
        } catch {
            errorHandler(error)
        }
    }

}
