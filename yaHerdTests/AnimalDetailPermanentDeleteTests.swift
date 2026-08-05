import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class AnimalDetailPermanentDeleteTests: XCTestCase {
    func testActiveAnimalCannotBePermanentlyDeleted() {
        let animalID = UUID()
        let repository = PermanentDeleteAnimalDetailRepository(
            detail: makeDetail(id: animalID, isArchived: false)
        )
        let viewModel = AnimalDetailViewModel()

        viewModel.load(
            animalID: animalID,
            using: repository,
            pastureRepository: PermanentDeletePastureReferenceDataReader()
        )
        viewModel.delete(animalID: animalID, using: repository)

        XCTAssertEqual(repository.deletedIDs, [])
        XCTAssertFalse(viewModel.didDelete)
        XCTAssertEqual(
            viewModel.errorMessage,
            AnimalValidationError.permanentDeleteRequiresArchive.localizedDescription
        )
    }

    func testArchivedAnimalCanBePermanentlyDeleted() {
        let animalID = UUID()
        let repository = PermanentDeleteAnimalDetailRepository(
            detail: makeDetail(id: animalID, isArchived: true)
        )
        let viewModel = AnimalDetailViewModel()

        viewModel.load(
            animalID: animalID,
            using: repository,
            pastureRepository: PermanentDeletePastureReferenceDataReader()
        )
        viewModel.delete(animalID: animalID, using: repository)

        XCTAssertEqual(repository.deletedIDs, [animalID])
        XCTAssertTrue(viewModel.didDelete)
        XCTAssertNil(viewModel.errorMessage)
    }

    private func makeDetail(id: UUID, isArchived: Bool) -> AnimalDetailSnapshot {
        AnimalDetailSnapshot(
            id: id,
            name: "Test Animal",
            displayTagNumber: "100",
            displayTagColorID: nil,
            sex: .female,
            animalType: .cow,
            birthDate: Date(timeIntervalSince1970: 1_700_000_000),
            status: .active,
            pastureID: nil,
            pastureName: nil,
            sireID: nil,
            sire: nil,
            damID: nil,
            dam: nil,
            distinguishingFeatures: [],
            saleDate: nil,
            salePrice: nil,
            reasonSold: nil,
            deathDate: nil,
            causeOfDeath: nil,
            statusReferenceID: nil,
            statusReferenceName: nil,
            isArchived: isArchived,
            archivedAt: isArchived ? .now : nil,
            archiveReason: isArchived ? "Test" : nil,
            activeTags: [],
            inactiveTags: [],
            location: .pasture,
            maternalOffspring: []
        )
    }
}

@MainActor
private final class PermanentDeleteAnimalDetailRepository: AnimalDetailRepository {
    private let detail: AnimalDetailSnapshot
    private(set) var deletedIDs: [UUID] = []

    init(detail: AnimalDetailSnapshot) {
        self.detail = detail
    }

    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
        id == detail.id ? detail : nil
    }

    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] {
        []
    }

    func fetchOffspringDraftSeed(forDamID _: UUID) throws -> OffspringDraftSeed? {
        nil
    }

    func update(id _: UUID, input _: AnimalInput) throws -> AnimalDetailSnapshot {
        detail
    }

    func delete(ids: [UUID]) throws {
        deletedIDs.append(contentsOf: ids)
    }

    func archive(ids _: [UUID]) throws {}

    func restore(ids _: [UUID]) throws {}

    func addTag(animalID _: UUID, input _: AnimalTagInput) throws -> AnimalDetailSnapshot {
        detail
    }

    func updateTag(
        animalID _: UUID,
        tagID _: UUID,
        input _: AnimalTagInput
    ) throws -> AnimalDetailSnapshot {
        detail
    }

    func promoteTag(animalID _: UUID, tagID _: UUID) throws -> AnimalDetailSnapshot {
        detail
    }

    func retireTag(animalID _: UUID, tagID _: UUID) throws -> AnimalDetailSnapshot {
        detail
    }
}

@MainActor
private final class PermanentDeletePastureReferenceDataReader: PastureReferenceDataReader {
    func fetchPastureOptions() throws -> [PastureOption] {
        []
    }
}
