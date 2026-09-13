import Foundation
import XCTest
@testable import yaHerd

final class WorkingQueueEditorIdentityTests: XCTestCase {
    func testMissingRefreshedQueueItemInvalidatesPresentation() {
        let presented = makeSnapshot()

        XCTAssertTrue(
            WorkingQueueEditorIdentity.invalidates(
                presented: presented,
                refreshed: nil
            )
        )
    }

    func testChangedAnimalIdentityInvalidatesPresentation() {
        let presented = makeSnapshot()
        let refreshed = makeSnapshot(
            id: presented.id,
            sessionID: presented.sessionID,
            animalID: UUID(),
            destinationPastureID: presented.destinationPastureID
        )

        XCTAssertTrue(
            WorkingQueueEditorIdentity.invalidates(
                presented: presented,
                refreshed: refreshed
            )
        )
    }

    func testChangedPersistedDestinationInvalidatesPresentation() {
        let presented = makeSnapshot()
        let refreshed = makeSnapshot(
            id: presented.id,
            sessionID: presented.sessionID,
            animalID: presented.animalID,
            destinationPastureID: UUID()
        )

        XCTAssertTrue(
            WorkingQueueEditorIdentity.invalidates(
                presented: presented,
                refreshed: refreshed
            )
        )
    }

    func testUnrelatedWorkDataChangesPreservePresentation() {
        let presented = makeSnapshot(observationNotes: "Draft source")
        let refreshed = makeSnapshot(
            id: presented.id,
            sessionID: presented.sessionID,
            animalID: presented.animalID,
            destinationPastureID: presented.destinationPastureID,
            observationNotes: "Imported persisted change"
        )

        XCTAssertFalse(
            WorkingQueueEditorIdentity.invalidates(
                presented: presented,
                refreshed: refreshed
            )
        )
    }

    func testChangedSourcePastureRequiresReviewWhenUsingSourcePasture() {
        let presented = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "North"
        )
        let refreshed = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "South"
        )

        XCTAssertTrue(
            WorkingQueueEditorIdentity.sourcePastureChangeRequiresReview(
                presented: presented,
                refreshed: refreshed,
                selectedDestinationPastureID: nil
            )
        )
    }

    func testRemovedSourcePastureRequiresReviewWhenUsingSourcePasture() {
        let presented = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "North"
        )
        let refreshed = WorkingQueueEditorSourcePastureReference(
            id: nil,
            name: nil
        )

        XCTAssertTrue(
            WorkingQueueEditorIdentity.sourcePastureChangeRequiresReview(
                presented: presented,
                refreshed: refreshed,
                selectedDestinationPastureID: nil
            )
        )
    }

    func testChangedSourcePasturePreservesExplicitDestinationSelection() {
        let presented = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "North"
        )
        let refreshed = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "South"
        )

        XCTAssertFalse(
            WorkingQueueEditorIdentity.sourcePastureChangeRequiresReview(
                presented: presented,
                refreshed: refreshed,
                selectedDestinationPastureID: UUID()
            )
        )
    }

    func testMissingSourcePastureBaselineRequiresReviewWhenUsingSourcePasture() {
        let refreshed = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "Current"
        )

        XCTAssertTrue(
            WorkingQueueEditorIdentity.sourcePastureChangeRequiresReview(
                presented: nil,
                refreshed: refreshed,
                selectedDestinationPastureID: nil
            )
        )
    }

    func testSourcePastureRenameDoesNotRequireReviewWhenIdentityIsStable() {
        let id = UUID()
        let presented = WorkingQueueEditorSourcePastureReference(
            id: id,
            name: "Old Name"
        )
        let refreshed = WorkingQueueEditorSourcePastureReference(
            id: id,
            name: "New Name"
        )

        XCTAssertFalse(
            WorkingQueueEditorIdentity.sourcePastureChangeRequiresReview(
                presented: presented,
                refreshed: refreshed,
                selectedDestinationPastureID: nil
            )
        )
    }

    func testAvailableSourcePastureCanBeUsed() {
        XCTAssertTrue(
            WorkingQueueEditorIdentity.canUseSourcePasture(
                WorkingQueueEditorSourcePastureReference(
                    id: UUID(),
                    name: "North"
                )
            )
        )
    }

    func testRemovedSourcePastureCannotBeUsed() {
        XCTAssertFalse(
            WorkingQueueEditorIdentity.canUseSourcePasture(
                WorkingQueueEditorSourcePastureReference(
                    id: nil,
                    name: nil
                )
            )
        )
    }

    func testUnverifiedSourcePastureCannotBeUsed() {
        XCTAssertFalse(
            WorkingQueueEditorIdentity.canUseSourcePasture(nil)
        )
    }

    func testPersistedCurrentSourceNormalizesToSourceSelection() {
        let sourceID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: sourceID,
            name: "North"
        )

        XCTAssertNil(
            WorkingQueueEditorIdentity.destinationPastureSelection(
                persistedDestinationPastureID: sourceID,
                sourcePasture: source
            )
        )
    }

    func testPersistedOldSourceRemainsExplicitWhenSessionSourceChanges() {
        let oldSourceID = UUID()
        let currentSource = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "South"
        )

        XCTAssertEqual(
            WorkingQueueEditorIdentity.destinationPastureSelection(
                persistedDestinationPastureID: oldSourceID,
                sourcePasture: currentSource
            ),
            oldSourceID
        )
    }

    func testSourcePastureSelectionSavesExactPresentedSourceIdentity() {
        let sourceID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: sourceID,
            name: "North"
        )

        XCTAssertEqual(
            WorkingQueueEditorIdentity.destinationPastureIDForSave(
                selectedDestinationPastureID: nil,
                sourcePasture: source
            ),
            sourceID
        )
    }

    func testExplicitDestinationOverridesSourcePastureForSave() {
        let source = WorkingQueueEditorSourcePastureReference(
            id: UUID(),
            name: "North"
        )
        let destinationID = UUID()

        XCTAssertEqual(
            WorkingQueueEditorIdentity.destinationPastureIDForSave(
                selectedDestinationPastureID: destinationID,
                sourcePasture: source
            ),
            destinationID
        )
    }

    private func makeSnapshot(
        id: UUID = UUID(),
        sessionID: UUID = UUID(),
        animalID: UUID? = UUID(),
        destinationPastureID: UUID? = UUID(),
        observationNotes: String = ""
    ) -> WorkingQueueItemEditorSnapshot {
        WorkingQueueItemEditorSnapshot(
            id: id,
            sessionID: sessionID,
            sessionDate: Date(timeIntervalSince1970: 0),
            sessionStatus: .active,
            sessionSourcePastureName: "Source",
            plannedTreatments: [],
            status: .queued,
            completedAt: nil,
            collectedFromPastureName: "Source",
            destinationPastureID: destinationPastureID,
            animalID: animalID,
            animalDisplayTagNumber: "1",
            animalDisplayTagColorID: nil,
            animalDamDisplayTagNumber: nil,
            animalDamDisplayTagColorID: nil,
            animalSex: .female,
            animalAgeInMonths: 24,
            treatmentRecords: [],
            pregnancyCheck: nil,
            castrationPerformedInSession: false,
            observationNotes: observationNotes
        )
    }
}

final class FieldCheckSessionIdentitySnapshotTests: XCTestCase {
    func testMissingPresentedFindingInvalidatesPresentation() {
        let animalID = UUID()
        let presentedFindingID = UUID()
        let identity = makeIdentitySnapshot(findings: [])

        XCTAssertTrue(
            identity.invalidates(
                presentedFinding: FieldCheckIdentityReference(
                    id: presentedFindingID,
                    relatedAnimalID: animalID
                ),
                presentedAnimalID: nil
            )
        )
    }

    func testRelinkedPresentedFindingInvalidatesPresentation() {
        let findingID = UUID()
        let presentedAnimalID = UUID()
        let identity = makeIdentitySnapshot(
            findings: [makeFinding(id: findingID, animalID: UUID())]
        )

        XCTAssertTrue(
            identity.invalidates(
                presentedFinding: FieldCheckIdentityReference(
                    id: findingID,
                    relatedAnimalID: presentedAnimalID
                ),
                presentedAnimalID: nil
            )
        )
    }

    func testUnrelatedFindingChangesPreservePresentedFinding() {
        let findingID = UUID()
        let animalID = UUID()
        let identity = makeIdentitySnapshot(
            findings: [
                makeFinding(id: findingID, animalID: animalID),
                makeFinding(id: UUID(), animalID: UUID())
            ]
        )

        XCTAssertFalse(
            identity.invalidates(
                presentedFinding: FieldCheckIdentityReference(
                    id: findingID,
                    relatedAnimalID: animalID
                ),
                presentedAnimalID: nil
            )
        )
    }

    func testMissingPresentedAnimalInvalidatesPresentation() {
        let presentedAnimalID = UUID()
        let identity = makeIdentitySnapshot(animalChecks: [])

        XCTAssertTrue(
            identity.invalidates(
                presentedFinding: nil,
                presentedAnimalID: presentedAnimalID
            )
        )
    }

    func testUnrelatedAnimalChangesPreservePresentedAnimal() {
        let presentedAnimalID = UUID()
        let identity = makeIdentitySnapshot(
            animalChecks: [
                makeAnimalCheck(animalID: presentedAnimalID),
                makeAnimalCheck(animalID: UUID())
            ]
        )

        XCTAssertFalse(
            identity.invalidates(
                presentedFinding: nil,
                presentedAnimalID: presentedAnimalID
            )
        )
    }

    private func makeIdentitySnapshot(
        animalChecks: [FieldCheckAnimalCheckSnapshot] = [],
        findings: [FieldCheckFindingSnapshot] = []
    ) -> FieldCheckSessionIdentitySnapshot {
        let detail = FieldCheckSessionDetailSnapshot(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 0),
            completedAt: nil,
            notes: "",
            pastureID: UUID(),
            pastureName: "North",
            expectedHeadCountSnapshot: animalChecks.count,
            quickCowCount: 0,
            quickHeiferCount: 0,
            quickCalfCount: 0,
            quickBullCount: 0,
            quickSteerCount: 0,
            animalChecks: animalChecks,
            findings: findings
        )
        return FieldCheckSessionIdentitySnapshot(detail: detail)
    }

    private func makeAnimalCheck(animalID: UUID) -> FieldCheckAnimalCheckSnapshot {
        FieldCheckAnimalCheckSnapshot(
            id: UUID(),
            animalID: animalID,
            displayTagNumber: "1",
            displayTagColorID: nil,
            damDisplayTagNumber: nil,
            damDisplayTagColorID: nil,
            animalName: "",
            animalSex: .female,
            animalType: .cow,
            wasExpectedAtStart: true,
            wasCounted: false,
            needsAttention: false,
            isMissing: false
        )
    }

    private func makeFinding(id: UUID, animalID: UUID?) -> FieldCheckFindingSnapshot {
        FieldCheckFindingSnapshot(
            id: id,
            recordedAt: Date(timeIntervalSince1970: 0),
            type: .waterIssue,
            severity: .warning,
            status: .open,
            note: "",
            animalID: animalID,
            animalDisplayTagNumber: nil,
            animalDisplayTagColorID: nil,
            pastureName: "North",
            sessionID: UUID()
        )
    }
}
