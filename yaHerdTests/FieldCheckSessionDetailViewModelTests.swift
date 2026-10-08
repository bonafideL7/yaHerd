import XCTest
@testable import yaHerd

@MainActor
final class FieldCheckSessionDetailViewModelTests: XCTestCase {
    func testRapidQuickCountUpdatesStayOptimisticAndCoalesceToLatestValue() async throws {
        let sessionID = UUID()
        let repository = FieldCheckSessionDetailRepositorySpy(
            detail: makeDetail(sessionID: sessionID, quickCowCount: 0)
        )
        repository.shouldBlockFirstQuickCountWrite = true
        let model = FieldCheckSessionDetailViewModel()

        XCTAssertTrue(model.load(sessionID: sessionID, using: repository))
        XCTAssertEqual(model.quickAnimalTypeCountsDraft[.cow], 0)

        model.updateQuickAnimalTypeCounts(
            sessionID: sessionID,
            counts: [.cow: 1],
            using: repository
        )
        await waitUntil { repository.quickCountUpdates.count == 1 }

        model.updateQuickAnimalTypeCounts(
            sessionID: sessionID,
            counts: [.cow: 2],
            using: repository
        )
        model.updateQuickAnimalTypeCounts(
            sessionID: sessionID,
            counts: [.cow: 3],
            using: repository
        )

        XCTAssertEqual(
            model.quickAnimalTypeCountsDraft[.cow],
            3,
            "Rapid input must render from the optimistic draft instead of the stale persisted snapshot."
        )

        repository.releaseFirstQuickCountWrite()

        await waitUntil {
            repository.quickCountUpdates.count == 2
                && model.detail?.quickCowCount == 3
        }

        XCTAssertEqual(
            repository.quickCountUpdates.map { $0[.cow, default: 0] },
            [1, 3],
            "While one save is in flight, intermediate values should coalesce to the latest requested count."
        )
        XCTAssertEqual(model.quickAnimalTypeCountsDraft[.cow], 3)
    }

    func testOptimisticQuickCountDecreaseImmediatelyRequiresFinishConfirmation() async throws {
        let sessionID = UUID()
        let repository = FieldCheckSessionDetailRepositorySpy(
            detail: makeDetail(sessionID: sessionID, quickCowCount: 3)
        )
        repository.shouldBlockFirstQuickCountWrite = true
        let model = FieldCheckSessionDetailViewModel()

        XCTAssertTrue(model.load(sessionID: sessionID, using: repository))
        let persistedDetail = try XCTUnwrap(model.detail)
        XCTAssertEqual(persistedDetail.remainingExpectedCount, 0)
        XCTAssertEqual(persistedDetail.countVariance, 0)

        model.updateQuickAnimalTypeCounts(
            sessionID: sessionID,
            counts: [.cow: 2],
            using: repository
        )
        await waitUntil { repository.quickCountUpdates.count == 1 }

        let optimisticProjection = model.countProjection(for: persistedDetail)

        XCTAssertEqual(
            persistedDetail.remainingExpectedCount,
            0,
            "The persisted snapshot intentionally remains stale while the quick-count save is blocked."
        )
        XCTAssertEqual(optimisticProjection.totalSeen, 2)
        XCTAssertEqual(optimisticProjection.remainingExpectedCount, 1)
        XCTAssertEqual(optimisticProjection.countVariance, -1)
        XCTAssertTrue(
            optimisticProjection.requiresFinishConfirmation,
            "Finish/Review must react to the optimistic quick-count draft before persistence refreshes the snapshot."
        )

        repository.releaseFirstQuickCountWrite()
        await waitUntil { model.detail?.quickCowCount == 2 }
    }

    func testCompleteSessionWaitsForQueuedQuickCounts() async throws {
        let sessionID = UUID()
        let repository = FieldCheckSessionDetailRepositorySpy(
            detail: makeDetail(sessionID: sessionID, quickCowCount: 0)
        )
        repository.shouldBlockFirstQuickCountWrite = true
        let model = FieldCheckSessionDetailViewModel()

        XCTAssertTrue(model.load(sessionID: sessionID, using: repository))

        model.updateQuickAnimalTypeCounts(
            sessionID: sessionID,
            counts: [.cow: 1],
            using: repository
        )
        await waitUntil { repository.quickCountUpdates.count == 1 }

        model.updateQuickAnimalTypeCounts(
            sessionID: sessionID,
            counts: [.cow: 3],
            using: repository
        )

        let completionTask = Task { @MainActor in
            await model.completeSession(sessionID: sessionID, using: repository)
        }

        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(
            repository.completeSessionCalls,
            0,
            "Finish must not overtake a pending quick-count transaction."
        )

        repository.releaseFirstQuickCountWrite()
        await completionTask.value

        XCTAssertEqual(
            repository.quickCountUpdates.map { $0[.cow, default: 0] },
            [1, 3]
        )
        XCTAssertEqual(repository.completeSessionCalls, 1)
        XCTAssertEqual(repository.detail.quickCowCount, 3)
        XCTAssertNotNil(repository.detail.completedAt)
    }

    func testAcceptedActionsResumeInInvocationOrderAfterQuickCountPersistence() async throws {
        let sessionID = UUID()
        let repository = FieldCheckSessionDetailRepositorySpy(
            detail: makeDetail(sessionID: sessionID, quickCowCount: 0)
        )
        repository.shouldBlockFirstQuickCountWrite = true
        let model = FieldCheckSessionDetailViewModel()

        XCTAssertTrue(model.load(sessionID: sessionID, using: repository))
        let animalCheckID = try XCTUnwrap(repository.detail.animalChecks.first?.id)

        model.updateQuickAnimalTypeCounts(
            sessionID: sessionID,
            counts: [.cow: 1],
            using: repository
        )
        await waitUntil { repository.quickCountUpdates.count == 1 }

        let markSeenTask = Task { @MainActor in
            await model.setAnimalCheckCounted(
                sessionID: sessionID,
                animalCheckID: animalCheckID,
                isCounted: true,
                using: repository
            )
        }

        for _ in 0..<20 {
            await Task.yield()
        }

        let completionTask = Task { @MainActor in
            await model.completeSession(sessionID: sessionID, using: repository)
        }

        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(repository.completeSessionCalls, 0)

        repository.releaseFirstQuickCountWrite()
        await markSeenTask.value
        await completionTask.value

        XCTAssertEqual(
            repository.operationLog,
            ["quickCount", "setCounted", "complete"],
            "Actions accepted while sharing a quick-count prerequisite must execute in invocation order after that prerequisite succeeds."
        )
        XCTAssertEqual(repository.completeSessionCalls, 1)
    }

    func testQueuedLaterActionAbortsWhenEarlierAcceptedActionFails() async throws {
        let sessionID = UUID()
        let repository = FieldCheckSessionDetailRepositorySpy(
            detail: makeDetail(sessionID: sessionID, quickCowCount: 0)
        )
        repository.shouldBlockSetCountedWrite = true
        repository.setCountedFailure = FieldCheckSessionDetailTestError.setCountedFailure
        let model = FieldCheckSessionDetailViewModel()

        XCTAssertTrue(model.load(sessionID: sessionID, using: repository))
        let animalCheckID = try XCTUnwrap(repository.detail.animalChecks.first?.id)

        let markSeenTask = Task { @MainActor in
            await model.setAnimalCheckCounted(
                sessionID: sessionID,
                animalCheckID: animalCheckID,
                isCounted: true,
                using: repository
            )
        }

        await waitUntil {
            repository.operationLog.contains("setCounted")
        }

        let completionTask = Task { @MainActor in
            await model.completeSession(sessionID: sessionID, using: repository)
        }

        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(repository.completeSessionCalls, 0)

        repository.releaseSetCountedWrite()
        await markSeenTask.value
        await completionTask.value

        XCTAssertEqual(
            repository.operationLog,
            ["setCounted"],
            "Later accepted actions must abort when an earlier queued action fails."
        )
        XCTAssertEqual(repository.completeSessionCalls, 0)
        XCTAssertNil(repository.detail.completedAt)
        XCTAssertNotNil(model.errorMessage)
    }

    func testCompleteSessionAbortsWhenQueuedQuickCountFails() async throws {
        let sessionID = UUID()
        let repository = FieldCheckSessionDetailRepositorySpy(
            detail: makeDetail(sessionID: sessionID, quickCowCount: 0)
        )
        repository.shouldBlockFirstQuickCountWrite = true
        repository.quickCountFailure = FieldCheckSessionDetailTestError.quickCountFailure
        let model = FieldCheckSessionDetailViewModel()

        XCTAssertTrue(model.load(sessionID: sessionID, using: repository))

        model.updateQuickAnimalTypeCounts(
            sessionID: sessionID,
            counts: [.cow: 1],
            using: repository
        )
        await waitUntil { repository.quickCountUpdates.count == 1 }

        let completionTask = Task { @MainActor in
            await model.completeSession(sessionID: sessionID, using: repository)
        }

        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(repository.completeSessionCalls, 0)

        repository.releaseFirstQuickCountWrite()
        await completionTask.value

        XCTAssertEqual(
            repository.completeSessionCalls,
            0,
            "A lifecycle mutation must abort when its queued quick-count prerequisite fails."
        )
        XCTAssertEqual(repository.detail.quickCowCount, 0)
        XCTAssertNil(repository.detail.completedAt)
        XCTAssertEqual(model.quickAnimalTypeCountsDraft[.cow], 0)
        XCTAssertNotNil(
            model.errorMessage,
            "The quick-count persistence error must remain visible instead of being cleared by a later mutation."
        )
    }

    func testCompletionAcceptanceRejectsNewDraftEditsUntilFailureReturnsControl() async throws {
        let sessionID = UUID()
        let repository = FieldCheckSessionDetailRepositorySpy(
            detail: makeDetail(sessionID: sessionID, quickCowCount: 0)
        )
        repository.notesFailure = FieldCheckSessionDetailTestError.notesFailure
        let model = FieldCheckSessionDetailViewModel()

        XCTAssertTrue(model.load(sessionID: sessionID, using: repository))
        model.updateNotesDraft("Before Finish")

        XCTAssertTrue(model.beginSessionCompletion())
        XCTAssertTrue(model.isCompletingSession)

        model.updateNotesDraft("After Finish")
        model.updateQuickAnimalTypeCounts(
            sessionID: sessionID,
            counts: [.cow: 1],
            using: repository
        )

        XCTAssertEqual(
            model.notesDraft,
            "Before Finish",
            "Notes accepted after Finish begins must be rejected instead of becoming unsavable draft state."
        )
        XCTAssertEqual(
            model.quickAnimalTypeCountsDraft[.cow],
            0,
            "Quick-count edits accepted after Finish begins must be rejected before persistence."
        )
        XCTAssertTrue(repository.quickCountUpdates.isEmpty)

        await model.completeSession(
            sessionID: sessionID,
            using: repository,
            completionAlreadyAccepted: true
        )

        XCTAssertFalse(model.isCompletingSession)
        XCTAssertNil(repository.detail.completedAt)
        XCTAssertNotNil(model.errorMessage)

        model.updateNotesDraft("Retry After Failure")
        XCTAssertEqual(
            model.notesDraft,
            "Retry After Failure",
            "A failed completion must return editing control so the user can correct and retry."
        )
    }

    func testCompleteSessionAbortsWhenNotesPersistenceFails() async throws {
        let sessionID = UUID()
        let repository = FieldCheckSessionDetailRepositorySpy(
            detail: makeDetail(sessionID: sessionID, quickCowCount: 0)
        )
        repository.notesFailure = FieldCheckSessionDetailTestError.notesFailure
        let model = FieldCheckSessionDetailViewModel()

        XCTAssertTrue(model.load(sessionID: sessionID, using: repository))
        model.updateNotesDraft("Unsaved field note")

        await model.completeSession(sessionID: sessionID, using: repository)

        XCTAssertEqual(
            repository.completeSessionCalls,
            0,
            "Finish must abort when its notes-persistence prerequisite fails."
        )
        XCTAssertEqual(repository.detail.notes, "")
        XCTAssertNil(repository.detail.completedAt)
        XCTAssertNotNil(model.errorMessage)
    }

    func testAnimalDetailActionsExecuteInInvocationOrder() async throws {
        let sessionID = UUID()
        let animalID = UUID()
        let fieldCheckRepository = FieldCheckSessionDetailRepositorySpy(
            detail: makeDetail(
                sessionID: sessionID,
                quickCowCount: 0,
                primaryAnimalID: animalID
            )
        )
        fieldCheckRepository.shouldBlockSetCountedWrite = true
        let animalRepository = FieldCheckAnimalDetailRepositorySpy(
            detail: makeAnimalDetail(id: animalID)
        )
        let model = FieldCheckAnimalDetailViewModel()

        model.load(
            animalID: animalID,
            sessionID: sessionID,
            animalRepository: animalRepository,
            fieldCheckRepository: fieldCheckRepository
        )

        let markSeenTask = Task { @MainActor in
            await model.setAnimalCheckCounted(
                animalID: animalID,
                sessionID: sessionID,
                isCounted: true,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        }

        await waitUntil {
            fieldCheckRepository.operationLog.contains("setCounted")
        }

        let markMissingTask = Task { @MainActor in
            await model.setAnimalCheckMissing(
                animalID: animalID,
                sessionID: sessionID,
                isMissing: true,
                animalRepository: animalRepository,
                fieldCheckRepository: fieldCheckRepository
            )
        }

        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(
            fieldCheckRepository.operationLog,
            ["setCounted"],
            "The later Animal-detail action must not enter persistence while the earlier accepted action is still pending."
        )

        fieldCheckRepository.releaseSetCountedWrite()
        await markSeenTask.value
        await markMissingTask.value

        XCTAssertEqual(
            fieldCheckRepository.operationLog,
            ["setCounted", "setMissing"],
            "Animal-detail Field Check actions must execute in invocation order."
        )
    }

    func testTrackedAnimalPickerSubmissionGateRejectsReentryUntilFinished() async {
        let model = FieldCheckTrackedAnimalPickerViewModel()
        let session = makeDetail(sessionID: UUID(), quickCowCount: 0)
        let reader = FieldCheckTrackedCandidateQuerySpy(animals: [])
        XCTAssertFalse(model.beginSelectionSubmission(), "Submission requires a complete candidate load.")
        await model.load(for: session, using: reader)

        XCTAssertTrue(model.beginSelectionSubmission())
        XCTAssertTrue(model.isSubmittingSelection)
        XCTAssertFalse(
            model.beginSelectionSubmission(),
            "A second tracked-animal selection must be rejected while the accepted move is pending."
        )

        model.endSelectionSubmission()

        XCTAssertFalse(model.isSubmittingSelection)
        XCTAssertTrue(
            model.beginSelectionSubmission(),
            "The picker should accept a new selection after the prior submission finishes."
        )
    }

    func testTrackedPickerUsesCompletePastureScopedCohortAndExcludesChecks() async throws {
        let session = makeDetail(sessionID: UUID(), quickCowCount: 0)
        let destinationID = try XCTUnwrap(session.pastureID)
        let checkedID = try XCTUnwrap(session.animalChecks.first?.animalID)
        let sourceAnimals = (0..<505).map { index in
            makeTrackedCandidate(
                tag: String(format: "FC%04d", index),
                pastureID: UUID()
            )
        }
        let alreadyChecked = makeTrackedCandidate(
            id: checkedID,
            tag: "ALREADY",
            pastureID: UUID()
        )
        let resident = makeTrackedCandidate(tag: "RESIDENT", pastureID: destinationID)
        let reader = FieldCheckTrackedCandidateQuerySpy(
            animals: sourceAnimals + [alreadyChecked, resident]
        )
        let model = FieldCheckTrackedAnimalPickerViewModel()
        await model.load(for: session, using: reader)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.loadErrorMessage)
        XCTAssertEqual(model.eligibleAnimals(
            forPastureID: destinationID,
            excluding: Set(session.animalChecks.compactMap(\.animalID))
        ).map(\.id), sourceAnimals.map(\.id))
        let query = await reader.lastQuery()
        XCTAssertEqual(query?.pastureScope, .notPasture(destinationID))
        XCTAssertEqual(query?.location, .any)
        XCTAssertTrue(query?.excludedAnimalIDs.contains(checkedID) == true)
        let count = await reader.fetchCount()
        XCTAssertEqual(count, 1, "Large rosters must use one consistent snapshot, not concatenated offset pages.")
    }

    func testTrackedPickerFailureClearsCandidatesAndAllowsRefresh() async {
        let session = makeDetail(sessionID: UUID(), quickCowCount: 0)
        let candidate = makeTrackedCandidate(tag: "READY", pastureID: UUID())
        let reader = FieldCheckTrackedCandidateQuerySpy(animals: [candidate])
        let model = FieldCheckTrackedAnimalPickerViewModel()
        await model.load(for: session, using: reader)
        XCTAssertEqual(model.animals.map(\.id), [candidate.id])

        await reader.setFailure(true)
        await model.load(for: session, using: reader)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(model.beginSelectionSubmission())
        XCTAssertTrue(model.animals.isEmpty)
        XCTAssertNotNil(model.loadErrorMessage)

        await reader.setFailure(false)
        await model.load(for: session, using: reader)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.loadErrorMessage)
        XCTAssertEqual(model.animals.map(\.id), [candidate.id])
    }

    func testTrackedPickerRejectsArchivedPastureWithoutQuery() async {
        let active = makeDetail(sessionID: UUID(), quickCowCount: 0)
        let archived = FieldCheckSessionDetailSnapshot(
            id: active.id,
            startedAt: active.startedAt,
            completedAt: active.completedAt,
            notes: active.notes,
            pastureID: active.pastureID,
            pastureName: active.pastureName,
            pastureArchivedAt: .now,
            isPastureArchived: true,
            expectedHeadCountSnapshot: active.expectedHeadCountSnapshot,
            quickCowCount: active.quickCowCount,
            quickHeiferCount: active.quickHeiferCount,
            quickCalfCount: active.quickCalfCount,
            quickBullCount: active.quickBullCount,
            quickSteerCount: active.quickSteerCount,
            animalChecks: active.animalChecks,
            findings: active.findings
        )
        let reader = FieldCheckTrackedCandidateQuerySpy(
            animals: [makeTrackedCandidate(tag: "NO", pastureID: UUID())]
        )
        let model = FieldCheckTrackedAnimalPickerViewModel()
        await model.load(for: archived, using: reader)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(model.beginSelectionSubmission())
        XCTAssertTrue(model.animals.isEmpty)
        let count = await reader.fetchCount()
        XCTAssertEqual(count, 0)
    }

    func testOlderTrackedPickerQueryCannotOverwriteRefreshedCohort() async {
        let session = makeDetail(sessionID: UUID(), quickCowCount: 0)
        let candidate = makeTrackedCandidate(tag: "NEW", pastureID: UUID())
        let reader = FieldCheckTrackedCandidateQuerySpy(
            animals: [candidate],
            pauseFirst: true
        )
        let model = FieldCheckTrackedAnimalPickerViewModel()
        let old = Task { @MainActor in
            await model.load(for: session, using: reader)
        }
        await reader.waitUntilPaused()
        await model.load(for: session, using: reader)
        XCTAssertEqual(model.animals.map(\.id), [candidate.id])
        await reader.releasePaused()
        await old.value
        XCTAssertEqual(model.animals.map(\.id), [candidate.id])
        XCTAssertTrue(model.hasLoaded)
    }

    private func makeTrackedCandidate(
        id: UUID = UUID(),
        tag: String,
        pastureID: UUID?
    ) -> AnimalSummary {
        AnimalSummary(
            id: id,
            name: "Tracked \\(tag)",
            displayTagNumber: tag,
            displayTagColorID: nil,
            damDisplayTagNumber: nil,
            damDisplayTagColorID: nil,
            sex: .female,
            animalType: .cow,
            firstDistinguishingFeature: nil,
            birthDate: .distantPast,
            status: .active,
            isArchived: false,
            pastureID: pastureID,
            pastureName: pastureID == nil ? nil : "Other",
            location: .pasture
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for the asynchronous Field Check state transition.")
    }

    private func makeDetail(
        sessionID: UUID,
        quickCowCount: Int,
        completedAt: Date? = nil,
        primaryAnimalID: UUID? = nil
    ) -> FieldCheckSessionDetailSnapshot {
        FieldCheckSessionDetailSnapshot(
            id: sessionID,
            startedAt: Date(timeIntervalSinceReferenceDate: 10_000),
            completedAt: completedAt,
            notes: "",
            pastureID: UUID(),
            pastureName: "Quick Count Test",
            expectedHeadCountSnapshot: 3,
            quickCowCount: quickCowCount,
            quickHeiferCount: 0,
            quickCalfCount: 0,
            quickBullCount: 0,
            quickSteerCount: 0,
            animalChecks: (1...3).map { index in
                FieldCheckAnimalCheckSnapshot(
                    id: UUID(),
                    animalID: index == 1 ? (primaryAnimalID ?? UUID()) : UUID(),
                    displayTagNumber: "QC-\(index)",
                    displayTagColorID: nil,
                    damDisplayTagNumber: nil,
                    damDisplayTagColorID: nil,
                    animalName: "Cow \(index)",
                    animalSex: .female,
                    animalType: .cow,
                    wasExpectedAtStart: true,
                    wasCounted: false,
                    needsAttention: false,
                    isMissing: false
                )
            },
            findings: []
        )
    }

    private func makeAnimalDetail(id: UUID) -> AnimalDetailSnapshot {
        AnimalDetailSnapshot(
            id: id,
            name: "Animal Detail Test Cow",
            displayTagNumber: "AD-1",
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
            maternalOffspring: []
        )
    }
}

@MainActor
private final class FieldCheckSessionDetailRepositorySpy:
    FieldCheckSessionDetailRepository,
    FieldCheckAnimalDetailRepository
{
    var detail: FieldCheckSessionDetailSnapshot
    var shouldBlockFirstQuickCountWrite = false
    var quickCountFailure: Error?
    var notesFailure: Error?
    var shouldBlockSetCountedWrite = false
    var setCountedFailure: Error?
    private var firstQuickCountContinuation: CheckedContinuation<Void, Never>?
    private var setCountedContinuation: CheckedContinuation<Void, Never>?

    private(set) var quickCountUpdates: [[AnimalType: Int]] = []
    private(set) var operationLog: [String] = []
    private(set) var completeSessionCalls = 0

    init(detail: FieldCheckSessionDetailSnapshot) {
        self.detail = detail
    }

    func fetchSessionDetail(id: UUID) throws -> FieldCheckSessionDetailSnapshot? {
        detail.id == id ? detail : nil
    }

    func updateQuickAnimalTypeCounts(
        sessionID: UUID,
        counts: [AnimalType: Int]
    ) async throws {
        quickCountUpdates.append(counts)
        operationLog.append("quickCount")

        if shouldBlockFirstQuickCountWrite,
           quickCountUpdates.count == 1 {
            await withCheckedContinuation { continuation in
                firstQuickCountContinuation = continuation
            }
        }

        if let quickCountFailure {
            throw quickCountFailure
        }

        detail = replacing(
            detail,
            quickCowCount: counts[.cow, default: 0]
        )
    }

    func releaseFirstQuickCountWrite() {
        shouldBlockFirstQuickCountWrite = false
        let continuation = firstQuickCountContinuation
        firstQuickCountContinuation = nil
        continuation?.resume()
    }

    func updateNotes(sessionID: UUID, notes: String) async throws {
        if let notesFailure {
            throw notesFailure
        }
        detail = replacing(detail, notes: notes)
    }

    func setAnimalCheckCounted(
        sessionID: UUID,
        animalCheckID: UUID,
        isCounted: Bool
    ) async throws {
        operationLog.append("setCounted")

        if shouldBlockSetCountedWrite {
            await withCheckedContinuation { continuation in
                setCountedContinuation = continuation
            }
        }

        if let setCountedFailure {
            throw setCountedFailure
        }
    }

    func releaseSetCountedWrite() {
        shouldBlockSetCountedWrite = false
        let continuation = setCountedContinuation
        setCountedContinuation = nil
        continuation?.resume()
    }

    func setAnimalCheckMissing(
        sessionID: UUID,
        animalCheckID: UUID,
        isMissing: Bool
    ) async throws {
        operationLog.append("setMissing")
    }

    func addTrackedAnimalToSession(
        sessionID: UUID,
        animalID: UUID,
        checkedAt: Date
    ) async throws {}

    func addFinding(
        sessionID: UUID,
        input: FieldCheckFindingInput
    ) async throws {}

    func updateFinding(
        sessionID: UUID,
        findingID: UUID,
        input: FieldCheckFindingInput
    ) async throws {}

    func updateFindingStatus(
        sessionID: UUID,
        findingID: UUID,
        status: FieldCheckFindingStatus
    ) async throws {}

    func deleteFinding(
        sessionID: UUID,
        findingID: UUID
    ) async throws {}

    func completeSession(id: UUID) async throws {
        operationLog.append("complete")
        completeSessionCalls += 1
        detail = replacing(
            detail,
            completedAt: .now,
            replacesCompletedAt: true
        )
    }

    func reopenSession(id: UUID) async throws {
        detail = replacing(
            detail,
            completedAt: nil,
            replacesCompletedAt: true
        )
    }

    private func replacing(
        _ source: FieldCheckSessionDetailSnapshot,
        notes: String? = nil,
        quickCowCount: Int? = nil,
        completedAt: Date? = nil,
        replacesCompletedAt: Bool = false
    ) -> FieldCheckSessionDetailSnapshot {
        FieldCheckSessionDetailSnapshot(
            id: source.id,
            startedAt: source.startedAt,
            completedAt: replacesCompletedAt ? completedAt : source.completedAt,
            notes: notes ?? source.notes,
            pastureID: source.pastureID,
            pastureName: source.pastureName,
            pastureArchivedAt: source.pastureArchivedAt,
            isPastureArchived: source.isPastureArchived,
            expectedHeadCountSnapshot: source.expectedHeadCountSnapshot,
            quickCowCount: quickCowCount ?? source.quickCowCount,
            quickHeiferCount: source.quickHeiferCount,
            quickCalfCount: source.quickCalfCount,
            quickBullCount: source.quickBullCount,
            quickSteerCount: source.quickSteerCount,
            animalChecks: source.animalChecks,
            findings: source.findings
        )
    }
}


@MainActor
private final class FieldCheckAnimalDetailRepositorySpy: AnimalDetailRepository {
    var detail: AnimalDetailSnapshot

    init(detail: AnimalDetailSnapshot) {
        self.detail = detail
    }

    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
        detail.id == id ? detail : nil
    }

    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] {
        []
    }

    func fetchOffspringDraftSeed(forDamID damID: UUID) throws -> OffspringDraftSeed? {
        nil
    }

    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot {
        detail
    }

    func delete(ids: [UUID]) throws {}
    func archive(ids: [UUID]) throws {}
    func restore(ids: [UUID]) throws {}

    func addTag(
        animalID: UUID,
        input: AnimalTagInput
    ) throws -> AnimalDetailSnapshot {
        detail
    }

    func updateTag(
        animalID: UUID,
        tagID: UUID,
        input: AnimalTagInput
    ) throws -> AnimalDetailSnapshot {
        detail
    }

    func promoteTag(
        animalID: UUID,
        tagID: UUID
    ) throws -> AnimalDetailSnapshot {
        detail
    }

    func retireTag(
        animalID: UUID,
        tagID: UUID
    ) throws -> AnimalDetailSnapshot {
        detail
    }
}

private enum FieldCheckSessionDetailTestError: LocalizedError {
    case quickCountFailure
    case notesFailure
    case setCountedFailure

    var errorDescription: String? {
        switch self {
        case .quickCountFailure:
            return "Injected quick-count failure."
        case .notesFailure:
            return "Injected notes failure."
        case .setCountedFailure:
            return "Injected set-counted failure."
        }
    }
}

private enum FieldCheckTrackedCandidateTestError: Error {
    case queryFailure
}

private actor FieldCheckTrackedCandidateQuerySpy: AnimalReferenceQueryReading {
    private let animals: [AnimalSummary]
    private var shouldFail = false
    private var queries: [AnimalReferenceQuery] = []
    private let pauseFirst: Bool
    private var paused: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    private var firstEntered = false

    init(animals: [AnimalSummary], pauseFirst: Bool = false) {
        self.animals = animals
        self.pauseFirst = pauseFirst
    }

    func setFailure(_ value: Bool) { shouldFail = value }
    func fetchCount() -> Int { queries.count }
    func lastQuery() -> AnimalReferenceQuery? { queries.last }

    func waitUntilPaused() async {
        if firstEntered { return }
        await withCheckedContinuation { entered = $0 }
    }

    func releasePaused() {
        paused?.resume()
        paused = nil
    }

    func fetchAnimalReferenceSnapshot(
        matching query: AnimalReferenceQuery
    ) async throws -> [AnimalSummary] {
        queries.append(query)
        if pauseFirst && queries.count == 1 {
            await withCheckedContinuation { continuation in
                paused = continuation
                firstEntered = true
                entered?.resume()
                entered = nil
            }
        }
        if shouldFail { throw FieldCheckTrackedCandidateTestError.queryFailure }
        let excluded = Set(query.excludedAnimalIDs)
        return animals.filter { animal in
            guard case .notPasture(let pastureID) = query.pastureScope else { return false }
            return animal.pastureID != pastureID
                && animal.status == .active
                && !animal.isArchived
                && !excluded.contains(animal.id)
        }
    }

    func fetchAnimalReferencePage(
        matching query: AnimalReferenceQuery,
        page: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        throw FieldCheckTrackedCandidateTestError.queryFailure
    }

    func containsAnimal(id: UUID) async throws -> Bool {
        animals.contains { $0.id == id }
    }
}
