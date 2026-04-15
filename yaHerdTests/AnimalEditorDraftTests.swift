import XCTest
@testable import yaHerd

final class AnimalEditorDraftTests: XCTestCase {
    func testHasChangesIsFalseForUnchangedActiveAnimalWithoutStatusDates() {
        let detail = makeDetailSnapshot(status: .active, saleDate: nil, deathDate: nil)

        let draft = AnimalEditorDraft(detail: detail)
        XCTAssertFalse(draft.hasChanges(comparedTo: detail))
    }

    func testHasChangesDetectsSaleDateOnlyWhenSold() {
        let soldDetail = makeDetailSnapshot(status: .sold, saleDate: Date(timeIntervalSince1970: 1_000), deathDate: nil)

        var draft = AnimalEditorDraft(detail: soldDetail)
        XCTAssertFalse(draft.hasChanges(comparedTo: soldDetail))

        draft.saleDate = Date(timeIntervalSince1970: 2_000)
        XCTAssertTrue(draft.hasChanges(comparedTo: soldDetail))

        let activeDetail = makeDetailSnapshot(status: .active, saleDate: nil, deathDate: nil)
        draft = AnimalEditorDraft(detail: activeDetail)
        draft.saleDate = Date(timeIntervalSince1970: 5_000)
        XCTAssertFalse(draft.hasChanges(comparedTo: activeDetail))
    }

    private func makeDetailSnapshot(status: AnimalStatus, saleDate: Date?, deathDate: Date?) -> AnimalDetailSnapshot {
        AnimalDetailSnapshot(
            id: UUID(),
            name: "Bessie",
            displayTagNumber: "12",
            displayTagColorID: nil,
            sex: .female,
            birthDate: .distantPast,
            status: status,
            pastureID: nil,
            pastureName: nil,
            sireID: nil,
            sire: nil,
            damID: nil,
            dam: nil,
            distinguishingFeatures: [],
            saleDate: saleDate,
            salePrice: nil,
            reasonSold: nil,
            deathDate: deathDate,
            causeOfDeath: nil,
            statusReferenceID: nil,
            statusReferenceName: nil,
            isArchived: false,
            archivedAt: nil,
            archiveReason: nil,
            activeTags: [],
            inactiveTags: [],
            location: .pasture
        )
    }
}
