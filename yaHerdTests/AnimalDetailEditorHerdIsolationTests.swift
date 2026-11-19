import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class AnimalDetailEditorHerdIsolationTests: XCTestCase {
    func testSavingAnOldDraftDoesNotUpdateAnotherHerd() {
        for change in SelectionChange.allCases {
            let originalHerdID = UUID()
            let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
            let animalID = UUID()
            let repository = AnimalDetailWriteProbe(animalID: animalID)
            let model = loadedEditor(animalID: animalID, repository: repository)
            model.beginEditing(selection: selection)

            change.apply(to: selection, originalHerdID: originalHerdID)
            model.save(
                animalID: animalID,
                defaultTagColorID: nil,
                using: repository,
                selection: selection
            )

            XCTAssertEqual(repository.updateCount, 0, "A stale \(change) edit must not update an animal")
            XCTAssertTrue(model.isEditing, "A rejected save must preserve the draft")
            XCTAssertNotNil(model.errorMessage)
        }
    }

    func testStatusEditorRejectsSaveAfterHerdSelectionRoundTrip() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let animalID = UUID()
        let repository = AnimalDetailWriteProbe(animalID: animalID)
        let model = loadedEditor(animalID: animalID, repository: repository)
        model.beginEditingStatus(.sold, selection: selection)

        selection.select(UUID())
        selection.select(herdID)
        model.save(
            animalID: animalID,
            defaultTagColorID: nil,
            using: repository,
            selection: selection
        )

        XCTAssertEqual(repository.updateCount, 0)
        XCTAssertTrue(model.isEditing)
    }

    func testSavingWithoutAnActiveHerdIsRejected() {
        let selection = AppCurrentHerdSelection()
        let animalID = UUID()
        let repository = AnimalDetailWriteProbe(animalID: animalID)
        let model = loadedEditor(animalID: animalID, repository: repository)

        model.beginEditing(selection: selection)
        model.save(
            animalID: animalID,
            defaultTagColorID: nil,
            using: repository,
            selection: selection
        )

        XCTAssertEqual(repository.updateCount, 0)
        XCTAssertFalse(model.isEditing)
    }

    func testSavingUnderUnchangedHerdStillUpdatesAnimal() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let animalID = UUID()
        let repository = AnimalDetailWriteProbe(animalID: animalID)
        let model = loadedEditor(animalID: animalID, repository: repository)
        model.beginEditing(selection: selection)

        model.save(
            animalID: animalID,
            defaultTagColorID: nil,
            using: repository,
            selection: selection
        )

        XCTAssertEqual(repository.updateCount, 1)
        XCTAssertEqual(repository.lastUpdatedID, animalID)
        XCTAssertFalse(model.isEditing)
        XCTAssertNil(model.errorMessage)
    }

    private func loadedEditor(
        animalID: UUID,
        repository: AnimalDetailWriteProbe
    ) -> AnimalDetailViewModel {
        let model = AnimalDetailViewModel()
        model.load(animalID: animalID, using: repository, pastureRepository: repository)
        XCTAssertNotNil(model.detail)
        return model
    }
}

@MainActor
private enum SelectionChange: CaseIterable {
    case differentHerd
    case roundTrip
    case revoked

    func apply(to selection: AppCurrentHerdSelection, originalHerdID: UUID) {
        switch self {
        case .differentHerd:
            selection.select(UUID())
        case .roundTrip:
            selection.select(UUID())
            selection.select(originalHerdID)
        case .revoked:
            selection.select(nil)
        }
    }
}

@MainActor
private final class AnimalDetailWriteProbe: AnimalDetailRepository, PastureReferenceDataReader {
    private let detail: AnimalDetailSnapshot
    private(set) var updateCount = 0
    private(set) var lastUpdatedID: UUID?

    init(animalID: UUID) {
        detail = AnimalDetailSnapshot(
            id: animalID,
            name: "Test Cow",
            displayTagNumber: "",
            displayTagColorID: nil,
            sex: .female,
            animalType: .cow,
            birthDate: .distantPast,
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
            isArchived: false,
            archivedAt: nil,
            archiveReason: nil,
            activeTags: [],
            inactiveTags: [],
            location: .pasture,
            maternalOffspringCountIncludingArchived: 0,
            maternalOffspring: []
        )
    }

    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
        id == detail.id ? detail : nil
    }

    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] { [] }
    func fetchPastureOptions() throws -> [PastureOption] { [] }
    func fetchOffspringDraftSeed(forDamID damID: UUID) throws -> OffspringDraftSeed? { nil }

    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot {
        updateCount += 1
        lastUpdatedID = id
        return detail
    }

    func delete(ids: [UUID]) throws { XCTFail("Unexpected delete") }
    func archive(ids: [UUID]) throws { XCTFail("Unexpected archive") }
    func restore(ids: [UUID]) throws { XCTFail("Unexpected restore") }

    func addTag(animalID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
        XCTFail("Unexpected tag creation")
        return detail
    }

    func updateTag(animalID: UUID, tagID: UUID, input: AnimalTagInput) throws -> AnimalDetailSnapshot {
        XCTFail("Unexpected tag update")
        return detail
    }

    func promoteTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
        XCTFail("Unexpected tag promotion")
        return detail
    }

    func retireTag(animalID: UUID, tagID: UUID) throws -> AnimalDetailSnapshot {
        XCTFail("Unexpected tag retirement")
        return detail
    }
}
