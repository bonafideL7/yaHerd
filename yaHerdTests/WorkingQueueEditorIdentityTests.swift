import Foundation
import XCTest
@testable import yaHerd

final class WorkingQueueEditorIdentityTests: XCTestCase {
    @MainActor
    func testEditorHerdIdentityRejectsSelectionSwitchAndReturnToSameHerd() throws {
        let herdA = UUID()
        let herdB = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdA)
        let identity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))

        XCTAssertTrue(identity.isCurrent(in: selection))

        selection.select(herdA)
        XCTAssertTrue(
            identity.isCurrent(in: selection),
            "Selecting the already active Herd must not invalidate the current editor."
        )

        selection.select(herdB)
        XCTAssertFalse(identity.isCurrent(in: selection))

        selection.select(herdA)
        XCTAssertFalse(
            identity.isCurrent(in: selection),
            "Returning to a Herd must not revive an editor from an earlier selection."
        )

        let reopened = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        XCTAssertTrue(reopened.isCurrent(in: selection))
    }

    @MainActor
    func testEditorHerdIdentityRequiresAnActiveSelectionAndRejectsRevocation() throws {
        let selection = AppCurrentHerdSelection()
        XCTAssertNil(WorkingQueueEditorHerdIdentity(selection: selection))

        selection.select(UUID())
        let identity = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        selection.revalidateActiveHerd(from: [])

        XCTAssertNil(selection.currentHerdID)
        XCTAssertFalse(identity.isCurrent(in: selection))
    }

    func testAsyncSireExistenceResultCannotEraseAnotherSelection() {
        let checkedID = UUID()
        let newerID = UUID()

        XCTAssertTrue(
            WorkingQueueEditorIdentity.shouldClearSelectedSire(
                checkedSireID: checkedID,
                currentSireID: checkedID,
                stillExists: false
            ),
            "A confirmed deletion clears only the selected sire that was checked."
        )
        XCTAssertFalse(
            WorkingQueueEditorIdentity.shouldClearSelectedSire(
                checkedSireID: checkedID,
                currentSireID: newerID,
                stillExists: false
            ),
            "A deleted earlier sire must not clear a different selection made while the read awaited."
        )
        XCTAssertFalse(
            WorkingQueueEditorIdentity.shouldClearSelectedSire(
                checkedSireID: checkedID,
                currentSireID: nil,
                stillExists: false
            ),
            "A user's explicit clear must remain cleared."
        )
        XCTAssertFalse(
            WorkingQueueEditorIdentity.shouldClearSelectedSire(
                checkedSireID: checkedID,
                currentSireID: checkedID,
                stillExists: true
            ),
            "Existing sire identities, including archived records, retain the current draft."
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
}

extension WorkingQueueEditorIdentityTests {
    func testSessionHistoricalSourceIDDoesNotBecomeUsableWhenLiveSourceIsUnavailable() {
        let historicalSourceID = UUID()
        let session = WorkingSessionDetailSnapshot(
            id: UUID(),
            date: .now,
            status: .active,
            sourcePastureID: historicalSourceID,
            sourcePastureName: "Deleted Historical Source",
            isSourcePastureAvailable: false,
            treatmentTemplateName: "Historical Source",
            plannedTreatments: [],
            queueItems: []
        )

        let reference = WorkingQueueEditorSourcePastureReference(session: session)

        XCTAssertNil(reference.id)
        XCTAssertEqual(reference.name, "Deleted Historical Source")
        XCTAssertFalse(WorkingQueueEditorIdentity.canUseSourcePasture(reference))
    }

    func testSessionLiveSourceKeepsHistoricalIdentityUsable() {
        let sourceID = UUID()
        let session = WorkingSessionDetailSnapshot(
            id: UUID(),
            date: .now,
            status: .active,
            sourcePastureID: sourceID,
            sourcePastureName: "Live Source",
            isSourcePastureAvailable: true,
            treatmentTemplateName: "Live Source",
            plannedTreatments: [],
            queueItems: []
        )

        let reference = WorkingQueueEditorSourcePastureReference(session: session)

        XCTAssertEqual(reference.id, sourceID)
        XCTAssertEqual(reference.name, "Live Source")
        XCTAssertTrue(WorkingQueueEditorIdentity.canUseSourcePasture(reference))
    }
}

extension WorkingQueueEditorIdentityTests {
    func testInitialSelectionRequiresReviewWhenHistoricalSourceIsDeleted() {
        let historicalSourceID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: nil,
            name: "Deleted Source"
        )

        let state = WorkingQueueEditorIdentity.validatedDestinationPastureSelection(
            persistedDestinationPastureID: historicalSourceID,
            sourcePasture: source,
            historicalSourcePastureID: historicalSourceID,
            availablePastureIDs: []
        )

        XCTAssertNil(state.selection)
        XCTAssertTrue(state.requiresReview)
    }

    func testInitialSelectionKeepsLiveExplicitDestinationWhenSourceIsDeleted() {
        let destinationID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: nil,
            name: "Deleted Source"
        )

        let state = WorkingQueueEditorIdentity.validatedDestinationPastureSelection(
            persistedDestinationPastureID: destinationID,
            sourcePasture: source,
            historicalSourcePastureID: UUID(),
            availablePastureIDs: [destinationID]
        )

        XCTAssertEqual(state.selection, destinationID)
        XCTAssertFalse(state.requiresReview)
    }

    func testInitialSelectionRequiresReviewWhenExplicitDestinationWasDeleted() {
        let sourceID = UUID()
        let deletedDestinationID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: sourceID,
            name: "Live Source"
        )

        let state = WorkingQueueEditorIdentity.validatedDestinationPastureSelection(
            persistedDestinationPastureID: deletedDestinationID,
            sourcePasture: source,
            historicalSourcePastureID: sourceID,
            availablePastureIDs: [sourceID]
        )

        XCTAssertNil(state.selection)
        XCTAssertTrue(state.requiresReview)
    }

    func testInitialSelectionNormalizesLiveSourceWithoutReview() {
        let sourceID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: sourceID,
            name: "Live Source"
        )

        let state = WorkingQueueEditorIdentity.validatedDestinationPastureSelection(
            persistedDestinationPastureID: sourceID,
            sourcePasture: source,
            historicalSourcePastureID: sourceID,
            availablePastureIDs: [sourceID]
        )

        XCTAssertNil(state.selection)
        XCTAssertFalse(state.requiresReview)
    }

    func testInitialSelectionPreservesExplicitDestinationWhenReferenceDataLoadFails() {
        let historicalSourceID = UUID()
        let destinationID = UUID()
        let source = WorkingQueueEditorSourcePastureReference(
            id: nil,
            name: "Deleted Source"
        )

        let state = WorkingQueueEditorIdentity.validatedDestinationPastureSelection(
            persistedDestinationPastureID: destinationID,
            sourcePasture: source,
            historicalSourcePastureID: historicalSourceID,
            availablePastureIDs: nil
        )

        XCTAssertEqual(state.selection, destinationID)
        XCTAssertFalse(state.requiresReview)
    }

}

extension WorkingQueueEditorIdentityTests {
    func testLiveSourceReferenceUsesCurrentPastureNameWhileKeepingHistoricalIdentity() {
        let sourceID = UUID()
        let session = WorkingSessionDetailSnapshot(
            id: UUID(),
            date: .now,
            status: .active,
            sourcePastureID: sourceID,
            sourcePastureName: "Historical Source Name",
            isSourcePastureAvailable: true,
            treatmentTemplateName: "Live Name",
            plannedTreatments: [],
            queueItems: []
        )

        let reference = WorkingQueueEditorSourcePastureReference(
            session: session,
            livePastures: [
                PastureOption(id: sourceID, name: "Current Source Name")
            ]
        )

        XCTAssertEqual(reference.id, sourceID)
        XCTAssertEqual(reference.name, "Current Source Name")
        XCTAssertEqual(session.sourcePastureName, "Historical Source Name")
    }

    func testUnavailableSourceReferenceKeepsHistoricalNameEvenWithStaleLiveOption() {
        let sourceID = UUID()
        let session = WorkingSessionDetailSnapshot(
            id: UUID(),
            date: .now,
            status: .active,
            sourcePastureID: sourceID,
            sourcePastureName: "Historical Deleted Source",
            isSourcePastureAvailable: false,
            treatmentTemplateName: "Deleted Source",
            plannedTreatments: [],
            queueItems: []
        )

        let reference = WorkingQueueEditorSourcePastureReference(
            session: session,
            livePastures: [
                PastureOption(id: sourceID, name: "Stale Reference Name")
            ]
        )

        XCTAssertNil(reference.id)
        XCTAssertEqual(reference.name, "Historical Deleted Source")
        XCTAssertFalse(WorkingQueueEditorIdentity.canUseSourcePasture(reference))
    }
}

@MainActor
final class WorkingSessionTreatmentPlanHerdIsolationTests: XCTestCase {
    func testQueuedSaveDoesNotReadOrWriteAfterHerdSwitch() async throws {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let original = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        let repository = SuspendedWorkingTreatmentPlanRepository()
        selection.select(UUID())

        let saved = try await WorkingSessionTreatmentPlanSave.execute(
            sessionID: repository.sessionID,
            initialTreatments: [],
            updatedTreatments: [WorkingTreatmentPlanItem(name: "Dewormer")],
            editorIdentity: original,
            selection: selection,
            repository: repository
        )
        XCTAssertFalse(saved)
        XCTAssertEqual(repository.fetchCount, 0)
        XCTAssertEqual(repository.updateCount, 0)
    }

    func testInFlightSaveDoesNotPublishAfterHerdRoundTrip() async throws {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let original = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        let repository = SuspendedWorkingTreatmentPlanRepository()
        repository.suspendUpdate = true

        let operation = Task {
            try await WorkingSessionTreatmentPlanSave.execute(
                sessionID: repository.sessionID,
                initialTreatments: [],
                updatedTreatments: [WorkingTreatmentPlanItem(name: "Dewormer")],
                editorIdentity: original,
                selection: selection,
                repository: repository
            )
        }
        await repository.waitForUpdate()
        let originalHerdID = try XCTUnwrap(selection.currentHerdID)
        selection.select(UUID())
        selection.select(originalHerdID)
        repository.completeUpdate()

        let saved = try await operation.value
        XCTAssertFalse(saved)
        XCTAssertEqual(repository.updateCount, 1)
    }

    func testUnchangedHerdCanSaveTreatmentPlan() async throws {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let original = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        let repository = SuspendedWorkingTreatmentPlanRepository()

        let saved = try await WorkingSessionTreatmentPlanSave.execute(
            sessionID: repository.sessionID,
            initialTreatments: [],
            updatedTreatments: [WorkingTreatmentPlanItem(name: "Dewormer")],
            editorIdentity: original,
            selection: selection,
            repository: repository
        )

        XCTAssertTrue(saved)
        XCTAssertEqual(repository.fetchCount, 1)
        XCTAssertEqual(repository.updateCount, 1)
    }

    func testChangedPlanCannotOverwriteMoreRecentChanges() async throws {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let original = try XCTUnwrap(WorkingQueueEditorHerdIdentity(selection: selection))
        let repository = SuspendedWorkingTreatmentPlanRepository()
        repository.plannedTreatments = [WorkingTreatmentPlanItem(name: "Recent Update")]

        do {
            _ = try await WorkingSessionTreatmentPlanSave.execute(
                sessionID: repository.sessionID,
                initialTreatments: [],
                updatedTreatments: [WorkingTreatmentPlanItem(name: "Stale Change")],
                editorIdentity: original,
                selection: selection,
                repository: repository
            )
            XCTFail("A treatment plan edited elsewhere must not be overwritten.")
        } catch let error as WorkingSessionTreatmentPlanSave.ValidationError {
            XCTAssertEqual(error, .treatmentsChanged)
        }
        XCTAssertEqual(repository.updateCount, 0)
    }
}

@MainActor
private final class SuspendedWorkingTreatmentPlanRepository: WorkingSessionDetailRepository {
    let sessionID = UUID()
    var plannedTreatments: [WorkingTreatmentPlanItem] = []
    var suspendUpdate = false
    private(set) var fetchCount = 0
    private(set) var updateCount = 0
    private var pendingUpdate: CheckedContinuation<Void, Never>?

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        fetchCount += 1
        guard id == sessionID else { return nil }
        return WorkingSessionDetailSnapshot(
            id: sessionID,
            date: .now,
            status: .active,
            sourcePastureID: nil,
            sourcePastureName: "North",
            isSourcePastureAvailable: false,
            treatmentTemplateName: nil,
            plannedTreatments: plannedTreatments,
            queueItems: []
        )
    }

    func updateSessionTreatments(id: UUID, plannedTreatments: [WorkingTreatmentPlanItem]) async throws {
        updateCount += 1
        if suspendUpdate {
            await withCheckedContinuation { continuation in
                pendingUpdate = continuation
            }
        }
        self.plannedTreatments = plannedTreatments
    }

    func waitForUpdate() async {
        while pendingUpdate == nil { await Task.yield() }
    }

    func completeUpdate() {
        let pending = pendingUpdate
        pendingUpdate = nil
        pending?.resume()
    }

    func deleteSession(id: UUID) async throws {}
    func reopenSession(id: UUID) async throws {}
}
