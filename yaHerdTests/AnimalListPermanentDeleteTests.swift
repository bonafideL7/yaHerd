import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class AnimalListPermanentDeleteTests: XCTestCase {
    func testLegacyHardDeleteSwipeRequestArchivesInsteadOfDeleting() {
        let animalID = UUID()
        let repository = PermanentDeleteAnimalListRepository()
        let viewModel = AnimalListViewModel()

        viewModel.performPrimarySwipeAction(
            animalID: animalID,
            hardDelete: true,
            using: repository,
            pastureRepository: PermanentDeleteAnimalListPastureReader()
        )

        XCTAssertEqual(repository.archivedIDs, [animalID])
        XCTAssertEqual(repository.deletedIDs, [])
        XCTAssertNil(viewModel.errorMessage)
    }
}

@MainActor
private final class PermanentDeleteAnimalListRepository: AnimalListRepository {
    private(set) var archivedIDs: [UUID] = []
    private(set) var deletedIDs: [UUID] = []

    func fetchAnimals() throws -> [AnimalSummary] {
        []
    }

    func fetchAnimalDetail(id _: UUID) throws -> AnimalDetailSnapshot? {
        nil
    }

    func create(input _: AnimalInput) throws -> AnimalDetailSnapshot {
        fatalError("Not used by this test.")
    }

    func update(id _: UUID, input _: AnimalInput) throws -> AnimalDetailSnapshot {
        fatalError("Not used by this test.")
    }

    func delete(ids: [UUID]) throws {
        deletedIDs.append(contentsOf: ids)
    }

    func archive(ids: [UUID]) throws {
        archivedIDs.append(contentsOf: ids)
    }

    func restore(ids _: [UUID]) throws {}

    func move(ids _: [UUID], toPastureID _: UUID?) throws {}
}

@MainActor
private final class PermanentDeleteAnimalListPastureReader: PastureReferenceDataReader {
    func fetchPastureOptions() throws -> [PastureOption] {
        []
    }
}
