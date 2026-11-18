import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class AddAnimalHerdIsolationTests: XCTestCase {
    func testDelayedSaveDoesNotCreateAnimalAfterHerdSwitch() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let repository = CreationProbe()
        let model = AddAnimalViewModel()

        selection.select(UUID())

        XCTAssertThrowsError(
            try model.save(
                defaultTagColorID: nil,
                using: repository,
                expectedHerdID: origin,
                expectedSelectionRevision: selection.selectionRevision,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(repository.createCount, 0)
    }

    func testRevokedSelectionDoesNotCreateAnimal() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let repository = CreationProbe()
        let model = AddAnimalViewModel()

        selection.select(nil)

        XCTAssertThrowsError(
            try model.save(
                defaultTagColorID: nil,
                using: repository,
                expectedHerdID: origin,
                expectedSelectionRevision: selection.selectionRevision,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(repository.createCount, 0)
    }

    func testSaveStillCallsRepositoryWhenHerdHasNotChanged() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let repository = CreationProbe()
        let model = AddAnimalViewModel()

        XCTAssertThrowsError(
            try model.save(
                defaultTagColorID: nil,
                using: repository,
                expectedHerdID: origin,
                expectedSelectionRevision: selection.selectionRevision,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is CreationProbe.ProbeError)
        }
        XCTAssertEqual(repository.createCount, 1)
    }

    func testReturningToOriginalHerdDoesNotCreateAnimalFromStaleSave() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let originatingRevision = selection.selectionRevision
        let repository = CreationProbe()
        let model = AddAnimalViewModel()

        selection.select(UUID())
        selection.select(origin)

        XCTAssertThrowsError(
            try model.save(
                defaultTagColorID: nil,
                using: repository,
                expectedHerdID: origin,
                expectedSelectionRevision: originatingRevision,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(repository.createCount, 0)
    }

    func testFreshSaveAfterReturningToOriginalHerdUsesCurrentRevision() {
        let origin = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: origin)
        let repository = CreationProbe()
        let model = AddAnimalViewModel()

        selection.select(UUID())
        selection.select(origin)

        XCTAssertThrowsError(
            try model.save(
                defaultTagColorID: nil,
                using: repository,
                expectedHerdID: origin,
                expectedSelectionRevision: selection.selectionRevision,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is CreationProbe.ProbeError)
        }
        XCTAssertEqual(repository.createCount, 1)
    }

    @MainActor
    private final class CreationProbe: AnimalEditorRepository {
        enum ProbeError: Error {
            case created
        }

        private(set) var createCount = 0

        func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] {
            []
        }

        func create(input: AnimalInput) throws -> AnimalDetailSnapshot {
            createCount += 1
            throw ProbeError.created
        }

        func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
            XCTFail("Saving should never add a tag after a failed creation")
            throw ProbeError.created
        }
    }
}
