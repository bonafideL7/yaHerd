import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class AnimalDetailEditorHerdIsolationTests: XCTestCase {
    func testAnimalDetailPresentationDoesNotExposeObsoleteHerdAfterSelectionChanges() {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let animalID = UUID()
        let repository = AnimalDetailWriteProbe(animalID: animalID)
        let model = loadedEditor(animalID: animalID, repository: repository, selection: selection)

        XCTAssertEqual(model.presentationDetail(for: selection)?.id, animalID)

        selection.select(UUID())
        XCTAssertNil(model.presentationDetail(for: selection), "Another Herd must not see the previous animal.")

        selection.select(originalHerdID)
        XCTAssertNil(model.presentationDetail(for: selection), "Switching away and back must not revive an old detail screen.")

        selection.select(nil)
        XCTAssertNil(model.presentationDetail(for: selection), "A revoked selection must hide the detail.")

        XCTAssertEqual(model.detail?.id, animalID, "Hiding presentation must not mutate stored records.")
    }

    func testSavingAnOldDraftDoesNotUpdateAnotherHerd() {
        for change in SelectionChange.allCases {
            let originalHerdID = UUID()
            let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
            let animalID = UUID()
            let repository = AnimalDetailWriteProbe(animalID: animalID)
            let model = loadedEditor(animalID: animalID, repository: repository, selection: selection)
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
        let model = loadedEditor(animalID: animalID, repository: repository, selection: selection)
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
        let model = loadedEditor(animalID: animalID, repository: repository, selection: selection)

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
        let model = loadedEditor(animalID: animalID, repository: repository, selection: selection)
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

    func testObsoleteAnimalDetailCannotEditArchiveRestoreOrDelete() {
        for change in SelectionChange.allCases {
            let herdID = UUID()
            let selection = AppCurrentHerdSelection(currentHerdID: herdID)
            let animalID = UUID()
            let repository = AnimalDetailWriteProbe(animalID: animalID, isArchived: true)
            let model = loadedEditor(animalID: animalID, repository: repository, selection: selection)
            let baselineReads = repository.fetchCount

            change.apply(to: selection, originalHerdID: herdID)

            model.beginEditing(selection: selection)
            model.beginEditingStatus(.sold, selection: selection)
            model.archive(animalID: animalID, using: repository, pastureRepository: repository, selection: selection)
            model.restore(animalID: animalID, using: repository, pastureRepository: repository, selection: selection)
            XCTAssertNil(model.preparePermanentDeleteReview(
                animalID: animalID, using: repository, selection: selection
            ))
            model.delete(animalID: animalID, using: repository, selection: selection)

            XCTAssertFalse(model.isEditing)
            XCTAssertFalse(model.didDelete)
            XCTAssertEqual(repository.updateCount, 0)
            XCTAssertEqual(repository.archiveCount, 0)
            XCTAssertEqual(repository.restoreCount, 0)
            XCTAssertEqual(repository.deleteCount, 0)
            XCTAssertEqual(repository.fetchCount, baselineReads)
            XCTAssertNotNil(model.errorMessage)
        }
    }

    func testCurrentAnimalDetailStillAllowsDestructiveActions() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let animalID = UUID()
        let repository = AnimalDetailWriteProbe(animalID: animalID, isArchived: true)
        let model = loadedEditor(animalID: animalID, repository: repository, selection: selection)

        model.archive(animalID: animalID, using: repository, pastureRepository: repository, selection: selection)
        model.restore(animalID: animalID, using: repository, pastureRepository: repository, selection: selection)
        XCTAssertNotNil(model.preparePermanentDeleteReview(
            animalID: animalID, using: repository, selection: selection
        ))
        model.delete(animalID: animalID, using: repository, selection: selection)

        XCTAssertEqual(repository.archiveCount, 1)
        XCTAssertEqual(repository.restoreCount, 1)
        XCTAssertEqual(repository.deleteCount, 1)
        XCTAssertTrue(model.didDelete)
    }

    private func loadedEditor(
        animalID: UUID,
        repository: AnimalDetailWriteProbe,
        selection: AppCurrentHerdSelection
    ) -> AnimalDetailViewModel {
        let model = AnimalDetailViewModel()
        model.captureViewingSelection(selection)
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
    private(set) var archiveCount = 0
    private(set) var restoreCount = 0
    private(set) var deleteCount = 0
    private(set) var fetchCount = 0

    init(animalID: UUID, isArchived: Bool = false) {
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
            isArchived: isArchived,
            archivedAt: isArchived ? .now : nil,
            archiveReason: nil,
            activeTags: [],
            inactiveTags: [],
            location: .pasture,
            maternalOffspringCountIncludingArchived: 0,
            maternalOffspring: []
        )
    }

    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
        fetchCount += 1
        return id == detail.id ? detail : nil
    }

    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] { [] }
    func fetchPastureOptions() throws -> [PastureOption] { [] }
    func fetchOffspringDraftSeed(forDamID damID: UUID) throws -> OffspringDraftSeed? { nil }

    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot {
        updateCount += 1
        lastUpdatedID = id
        return detail
    }

    func delete(ids: [UUID]) throws { deleteCount += 1 }
    func archive(ids: [UUID]) throws { archiveCount += 1 }
    func restore(ids: [UUID]) throws { restoreCount += 1 }

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
