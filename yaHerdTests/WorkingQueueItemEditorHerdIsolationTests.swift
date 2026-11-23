import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class WorkingQueueItemEditorHerdIsolationTests: XCTestCase {
    func testTagReplacementDoesNotStartAfterHerdSwitch() async {
        let herdA = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdA)
        let repository = TagReplacementRepositorySpy()
        let model = makeModel(repository: repository, selection: selection)

        selection.select(UUID())
        await model.replacePrimaryTag(number: "NEW", colorID: nil)

        XCTAssertEqual(repository.replacementCalls, 0)
        XCTAssertEqual(model.snapshot?.animalDisplayTagNumber, "OLD")
        XCTAssertNil(model.errorMessage)
    }

    func testTagReplacementDoesNotStartAfterReturningToOriginalHerd() async {
        let herdA = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdA)
        let repository = TagReplacementRepositorySpy()
        let model = makeModel(repository: repository, selection: selection)

        selection.select(UUID())
        selection.select(herdA)
        await model.replacePrimaryTag(number: "NEW", colorID: nil)

        XCTAssertEqual(repository.replacementCalls, 0)
        XCTAssertEqual(model.snapshot?.animalDisplayTagNumber, "OLD")
        XCTAssertNil(model.errorMessage)
    }

    func testLateTagReplacementSuccessDoesNotPublishAfterHerdRoundTrip() async {
        let herdA = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdA)
        let repository = TagReplacementRepositorySpy()
        let model = makeModel(repository: repository, selection: selection)

        let operation = Task { @MainActor in
            await model.replacePrimaryTag(number: "NEW", colorID: nil)
        }
        await waitForReplacement(repository)
        selection.select(UUID())
        selection.select(herdA)
        repository.succeedReplacement()
        await operation.value

        XCTAssertEqual(repository.replacementCalls, 1)
        XCTAssertEqual(model.snapshot?.animalDisplayTagNumber, "OLD")
        XCTAssertNil(model.errorMessage)
    }

    func testLateTagReplacementFailureDoesNotPublishAfterHerdRoundTrip() async {
        let herdA = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdA)
        let repository = TagReplacementRepositorySpy()
        let model = makeModel(repository: repository, selection: selection)

        let operation = Task { @MainActor in
            await model.replacePrimaryTag(number: "NEW", colorID: nil)
        }
        await waitForReplacement(repository)
        selection.select(UUID())
        selection.select(herdA)
        repository.failReplacement()
        await operation.value

        XCTAssertNil(model.errorMessage)
    }

    func testLateTagReplacementSuccessDoesNotPublishAfterHerdSwitch() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let repository = TagReplacementRepositorySpy()
        let model = makeModel(repository: repository, selection: selection)

        let operation = Task { @MainActor in
            await model.replacePrimaryTag(number: "NEW", colorID: nil)
        }
        await waitForReplacement(repository)
        selection.select(UUID())
        repository.succeedReplacement()
        await operation.value

        XCTAssertEqual(repository.replacementCalls, 1)
        XCTAssertEqual(model.snapshot?.animalDisplayTagNumber, "OLD")
        XCTAssertNil(model.errorMessage)
    }

    func testLateTagReplacementErrorDoesNotAppearAfterHerdSwitch() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let repository = TagReplacementRepositorySpy()
        let model = makeModel(repository: repository, selection: selection)

        let operation = Task { @MainActor in
            await model.replacePrimaryTag(number: "NEW", colorID: nil)
        }
        await waitForReplacement(repository)
        selection.select(UUID())
        repository.failReplacement()
        await operation.value

        XCTAssertNil(model.errorMessage)
    }

    func testTagReplacementStillUpdatesSnapshotWithinSameHerd() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let repository = TagReplacementRepositorySpy()
        let model = makeModel(repository: repository, selection: selection)

        let operation = Task { @MainActor in
            await model.replacePrimaryTag(number: "NEW", colorID: nil)
        }
        await waitForReplacement(repository)
        repository.succeedReplacement()
        await operation.value

        XCTAssertEqual(model.snapshot?.animalDisplayTagNumber, "NEW")
        XCTAssertNil(model.errorMessage)
    }

    func testHerdSwitchInvalidatesEditorSnapshotAndPreventsCrossHerdReload() {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let repository = TagReplacementRepositorySpy()
        let model = makeModel(repository: repository, selection: selection)
        XCTAssertNotNil(model.snapshot)
        XCTAssertEqual(repository.fetchCount, 1)

        selection.select(UUID())
        model.invalidateForHerdChange()
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.errorMessage)

        model.load()
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(repository.fetchCount, 1, "Obsolete editors must not query the newly selected Herd.")
    }

    func testHerdRoundTripCannotRestoreInvalidatedEditorSnapshot() {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let repository = TagReplacementRepositorySpy()
        let model = makeModel(repository: repository, selection: selection)

        selection.select(UUID())
        selection.select(originalHerdID)
        model.invalidateForHerdChange()
        model.load()

        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(repository.fetchCount, 1, "Returning to the original UUID must not revive an obsolete editor.")
    }

    private func makeModel(
        repository: TagReplacementRepositorySpy,
        selection: AppCurrentHerdSelection
    ) -> WorkingQueueItemEditorViewModel {
        let model = WorkingQueueItemEditorViewModel(
            sessionID: repository.sessionID,
            queueItemID: repository.queueItemID,
            repository: repository
        )
        model.configure(repository: repository, herdSelection: selection)
        model.load()
        return model
    }

    private func waitForReplacement(_ repository: TagReplacementRepositorySpy) async {
        for _ in 0..<1_000 {
            if repository.replacementCalls > 0 { return }
            await Task.yield()
        }
        XCTFail("Tag replacement did not begin.")
    }
}

@MainActor
private final class TagReplacementRepositorySpy: WorkingQueueItemEditingRepository {
    let sessionID = UUID()
    let queueItemID = UUID()
    private(set) var replacementCalls = 0
    private(set) var fetchCount = 0
    private var replacementContinuation: CheckedContinuation<WorkingQueueItemEditorSnapshot, Error>?

    func fetchQueueItemEditor(sessionID: UUID, queueItemID: UUID) throws -> WorkingQueueItemEditorSnapshot? {
        fetchCount += 1
        return snapshot(tag: "OLD")
    }

    func replacePrimaryTag(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingTagReplacementInput
    ) async throws -> WorkingQueueItemEditorSnapshot {
        replacementCalls += 1
        return try await withCheckedThrowingContinuation { continuation in
            replacementContinuation = continuation
        }
    }

    func succeedReplacement() {
        replacementContinuation?.resume(returning: snapshot(tag: "NEW"))
        replacementContinuation = nil
    }

    func failReplacement() {
        replacementContinuation?.resume(throwing: WorkingRepositoryError.tagReplacementUnavailable)
        replacementContinuation = nil
    }

    func saveEdits(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingSessionAnimalEditInput
    ) async throws {}

    func updateSessionTreatments(
        id: UUID,
        plannedTreatments: [WorkingTreatmentPlanItem]
    ) async throws {}

    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) async throws {}

    private func snapshot(tag: String) -> WorkingQueueItemEditorSnapshot {
        WorkingQueueItemEditorSnapshot(
            id: queueItemID,
            sessionID: sessionID,
            sessionDate: .now,
            sessionStatus: .active,
            sessionSourcePastureName: nil,
            plannedTreatments: [],
            status: .queued,
            completedAt: nil,
            collectedFromPastureName: nil,
            destinationPastureID: nil,
            animalID: UUID(),
            animalDisplayTagNumber: tag,
            animalDisplayTagColorID: nil,
            animalDamDisplayTagNumber: nil,
            animalDamDisplayTagColorID: nil,
            animalSex: .unknown,
            animalAgeInMonths: 12,
            treatmentRecords: [],
            pregnancyCheck: nil,
            castrationPerformedInSession: false,
            observationNotes: ""
        )
    }
}
