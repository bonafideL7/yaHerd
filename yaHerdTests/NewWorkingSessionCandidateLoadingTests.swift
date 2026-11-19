import XCTest
@testable import yaHerd

@MainActor
final class NewWorkingSessionCandidateLoadingTests: XCTestCase {
    func testFailedTemplateListKeepsSetupBlockedAfterSuccessfulCandidatePages() async {
        let pastureID = UUID()
        let animal = makeCandidate(tag: "T01", pastureID: pastureID)
        let reader = WorkingSetupCandidateReader(animalsByPasture: [pastureID: [animal]])
        let model = NewWorkingSessionViewModel(
            pastureRepository: WorkingSetupPastureReader(pastureID: pastureID),
            animalReferenceQueryReader: reader,
            workingRepository: WorkingSetupTemplateRepository(failList: true)
        )

        model.load()
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.hasLoadedSetupSuccessfully)
        XCTAssertTrue(model.pastures.isEmpty, "Do not publish Pastures without the required templates.")
        XCTAssertTrue(model.templates.isEmpty)
        let setupError = model.setupLoadErrorMessage
        XCTAssertNotNil(setupError)
        XCTAssertEqual(model.errorMessage, setupError)

        // Even if a candidate request completes, it has no authority to clear
        // setup failures or make an incomplete Working setup usable.
        await model.loadEligibleAnimals(pastureID: pastureID)
        XCTAssertEqual(model.eligibleAnimals(pastureID: pastureID).map(\.id), [animal.id])
        XCTAssertFalse(model.hasLoadedSetupSuccessfully)
        XCTAssertEqual(model.setupLoadErrorMessage, setupError)
        XCTAssertEqual(model.errorMessage, setupError)

        model.errorMessage = nil // user dismisses the alert
        XCTAssertEqual(model.setupLoadErrorMessage, setupError)
        XCTAssertFalse(model.hasLoadedSetupSuccessfully)

        // Retrying both healthy setup readers restores one complete setup.
        model.configure(
            pastureRepository: WorkingSetupPastureReader(pastureID: pastureID),
            animalReferenceQueryReader: reader,
            workingRepository: WorkingSetupTemplateRepository()
        )
        model.load()
        XCTAssertTrue(model.hasLoadedSetupSuccessfully)
        XCTAssertNil(model.setupLoadErrorMessage)
        XCTAssertEqual(model.pastures.map(\.id), [pastureID])
        XCTAssertNil(model.errorMessage)
    }

    func testFailedPastureReadCannotExposeTemplatesOrEnableSetup() async {
        let pastureID = UUID()
        let model = NewWorkingSessionViewModel(
            pastureRepository: WorkingSetupPastureReader(pastureID: pastureID, shouldFail: true),
            animalReferenceQueryReader: WorkingSetupCandidateReader(
                animalsByPasture: [pastureID: [makeCandidate(tag: "P01", pastureID: pastureID)]]
            ),
            workingRepository: WorkingSetupTemplateRepository()
        )
        model.load()
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.hasLoadedSetupSuccessfully)
        XCTAssertTrue(model.pastures.isEmpty)
        XCTAssertTrue(model.templates.isEmpty)
        let error = model.setupLoadErrorMessage
        XCTAssertNotNil(error)

        await model.loadEligibleAnimals(pastureID: pastureID)
        XCTAssertEqual(model.setupLoadErrorMessage, error)
        XCTAssertEqual(model.errorMessage, error)
        XCTAssertFalse(model.hasLoadedSetupSuccessfully)
    }

    func testCandidateRefreshDoesNotEraseTemplateDetailFailure() async {
        let pastureID = UUID()
        let model = NewWorkingSessionViewModel(
            pastureRepository: WorkingSetupPastureReader(pastureID: pastureID),
            animalReferenceQueryReader: WorkingSetupCandidateReader(
                animalsByPasture: [pastureID: [makeCandidate(tag: "D01", pastureID: pastureID)]]
            ),
            workingRepository: WorkingSetupTemplateRepository(failDetail: true)
        )
        model.load()
        XCTAssertTrue(model.hasLoadedSetupSuccessfully)
        XCTAssertNil(model.templateDetail(id: UUID()))
        let templateError = model.errorMessage
        XCTAssertNotNil(templateError)

        await model.loadEligibleAnimals(pastureID: pastureID)
        XCTAssertEqual(model.loadedPastureID, pastureID)
        XCTAssertEqual(model.errorMessage, templateError)
    }

    func testSelectedPastureLoadsEveryPageWithoutShowingAnotherPasture() async {
        let firstPastureID = UUID()
        let secondPastureID = UUID()
        let first = (0..<503).map {
            makeCandidate(tag: String(format: "%03d", $0), pastureID: firstPastureID)
        }
        let other = makeCandidate(tag: "999", pastureID: secondPastureID)
        let reader = WorkingSetupCandidateReader(
            animalsByPasture: [
                firstPastureID: first,
                secondPastureID: [other]
            ]
        )
        let model = NewWorkingSessionViewModel(
            pastureRepository: EmptyPastureRepository(),
            animalReferenceQueryReader: reader,
            workingRepository: EmptyWorkingRepository()
        )

        await model.loadEligibleAnimals(pastureID: firstPastureID)
        XCTAssertFalse(model.isLoadingAnimals)
        XCTAssertEqual(model.loadedPastureID, firstPastureID)
        XCTAssertEqual(model.eligibleAnimals(pastureID: firstPastureID).map(\.id), first.map(\.id))
        XCTAssertTrue(model.eligibleAnimals(pastureID: secondPastureID).isEmpty)
        let snapshotCount = await reader.snapshotRequestCount(for: firstPastureID)
        XCTAssertEqual(snapshotCount, 1)

        model.clearCandidates(for: secondPastureID)
        XCTAssertTrue(model.isLoadingAnimals)
        XCTAssertNil(model.loadedPastureID)
        XCTAssertTrue(model.eligibleAnimals(pastureID: firstPastureID).isEmpty)
        await model.loadEligibleAnimals(pastureID: secondPastureID)
        XCTAssertEqual(model.eligibleAnimals(pastureID: secondPastureID).map(\.id), [other.id])

        model.clearCandidates(for: nil)
        await model.loadEligibleAnimals(pastureID: nil)
        XCTAssertTrue(model.animals.isEmpty)
        XCTAssertNil(model.loadedPastureID)
        XCTAssertFalse(model.isLoadingAnimals)
    }

    func testFailedSnapshotHydrationNeverPublishesPartialCandidatesAndAllowsRetry() async {
        let pastureID = UUID()
        let animals = (0..<505).map {
            makeCandidate(tag: String(format: "%03d", $0), pastureID: pastureID)
        }
        let reader = WorkingSetupCandidateReader(animalsByPasture: [pastureID: animals])
        await reader.setFailureOffset(ReadPageRequest.maximumLimit)

        let model = NewWorkingSessionViewModel(
            pastureRepository: EmptyPastureRepository(),
            animalReferenceQueryReader: reader,
            workingRepository: EmptyWorkingRepository()
        )
        await model.loadEligibleAnimals(pastureID: pastureID)
        XCTAssertNil(model.loadedPastureID)
        XCTAssertTrue(model.eligibleAnimals(pastureID: pastureID).isEmpty)
        XCTAssertFalse(model.isLoadingAnimals)
        XCTAssertNotNil(model.errorMessage)

        await reader.setFailureOffset(nil)
        await model.loadEligibleAnimals(pastureID: pastureID)
        XCTAssertEqual(model.eligibleAnimals(pastureID: pastureID).count, animals.count)
        XCTAssertEqual(model.loadedPastureID, pastureID)
        XCTAssertNil(model.errorMessage)
    }

    func testOlderPastureRequestCannotOverwriteNewerCandidates() async {
        let firstPastureID = UUID()
        let secondPastureID = UUID()
        let first = makeCandidate(tag: "1", pastureID: firstPastureID)
        let second = makeCandidate(tag: "2", pastureID: secondPastureID)
        let reader = WorkingSetupCandidateReader(
            animalsByPasture: [
                firstPastureID: [first],
                secondPastureID: [second]
            ],
            pausedPastureID: firstPastureID
        )
        let model = NewWorkingSessionViewModel(
            pastureRepository: EmptyPastureRepository(),
            animalReferenceQueryReader: reader,
            workingRepository: EmptyWorkingRepository()
        )

        let olderRequest = Task {
            await model.loadEligibleAnimals(pastureID: firstPastureID)
        }
        await reader.waitForPausedRequest()
        model.clearCandidates(for: secondPastureID)
        await model.loadEligibleAnimals(pastureID: secondPastureID)

        await reader.resumePausedRequest()
        await olderRequest.value

        XCTAssertEqual(model.loadedPastureID, secondPastureID)
        XCTAssertEqual(model.animals.map(\.id), [second.id])
        XCTAssertTrue(model.eligibleAnimals(pastureID: firstPastureID).isEmpty)
    }


    func testObsoleteCandidateReadCannotPublishAfterHerdSelectionRoundTrip() async {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let pastureID = UUID()
        let animal = makeCandidate(tag: "A01", pastureID: pastureID)
        let reader = WorkingSetupCandidateReader(
            animalsByPasture: [pastureID: [animal]],
            pausedPastureID: pastureID
        )
        let model = NewWorkingSessionViewModel(
            pastureRepository: EmptyPastureRepository(),
            animalReferenceQueryReader: reader,
            workingRepository: EmptyWorkingRepository()
        )

        let oldRead = Task {
            await model.loadEligibleAnimals(
                pastureID: pastureID, currentHerdSelection: selection
            )
        }
        await reader.waitForPausedRequest()
        selection.select(UUID())
        selection.select(originalHerdID)
        await reader.resumePausedRequest()
        await oldRead.value

        XCTAssertNil(model.loadedPastureID)
        XCTAssertTrue(model.animals.isEmpty)
        XCTAssertFalse(model.hasCurrentCandidates(pastureID: pastureID, selection: selection))
        XCTAssertNil(model.errorMessage)

        model.configure(
            pastureRepository: EmptyPastureRepository(),
            animalReferenceQueryReader: WorkingSetupCandidateReader(
                animalsByPasture: [pastureID: [animal]]
            ),
            workingRepository: EmptyWorkingRepository()
        )
        await model.loadEligibleAnimals(
            pastureID: pastureID, currentHerdSelection: selection
        )

        XCTAssertEqual(model.animals.map(\.id), [animal.id])
        XCTAssertTrue(model.hasCurrentCandidates(pastureID: pastureID, selection: selection))
        selection.select(nil)
        XCTAssertFalse(model.hasCurrentCandidates(pastureID: pastureID, selection: selection))
    }

    func testObsoleteCandidateFailureDoesNotExposeAnotherHerdError() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let pastureID = UUID()
        let reader = WorkingSetupCandidateReader(
            animalsByPasture: [pastureID: [makeCandidate(tag: "A02", pastureID: pastureID)]],
            pausedPastureID: pastureID
        )
        await reader.setFailureOffset(0)
        let model = NewWorkingSessionViewModel(
            pastureRepository: EmptyPastureRepository(),
            animalReferenceQueryReader: reader,
            workingRepository: EmptyWorkingRepository()
        )

        let oldRead = Task {
            await model.loadEligibleAnimals(
                pastureID: pastureID, currentHerdSelection: selection
            )
        }
        await reader.waitForPausedRequest()
        selection.select(UUID())
        await reader.resumePausedRequest()
        await oldRead.value

        XCTAssertNil(model.loadedPastureID)
        XCTAssertTrue(model.animals.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.candidateLoadErrorMessage)
        XCTAssertFalse(model.hasCurrentCandidates(pastureID: pastureID, selection: selection))
    }

    func testSessionStartDoesNotRunAfterSwitchingHerdsBeforeSubmission() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionStartRepository()
        let model = NewWorkingSessionViewModel(
            pastureRepository: EmptyPastureRepository(),
            workingRepository: repository
        )

        selection.select(UUID())
        let result = try await model.startSession(
            date: .now,
            pastureID: UUID(),
            treatmentTemplateName: nil,
            plannedTreatments: [],
            animalIDs: nil,
            originatingHerdID: originatingHerdID,
            currentHerdSelection: selection,
            selectionIsUnchanged: {
                selection.selectionRevision == originatingSelectionRevision
            }
        )

        XCTAssertNil(result)
        XCTAssertEqual(repository.startCallCount, 0)
    }

    func testCompletedSessionStartIsDiscardedAfterSwitchingHerds() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionStartRepository()
        let model = NewWorkingSessionViewModel(
            pastureRepository: EmptyPastureRepository(),
            workingRepository: repository
        )
        let savedSessionID = UUID()

        let start = Task {
            try await model.startSession(
                date: .now,
                pastureID: UUID(),
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: nil,
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: {
                    selection.selectionRevision == originatingSelectionRevision
                }
            )
        }
        await repository.waitUntilStarted()
        selection.select(UUID())
        repository.complete(with: savedSessionID)

        let result = try await start.value
        XCTAssertNil(result)
        XCTAssertEqual(repository.startCallCount, 1, "The initial Herd transaction must not be duplicated.")
    }

    func testCompletedSessionStartIsDiscardedAfterHerdSelectionRoundTrip() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionStartRepository()
        let model = NewWorkingSessionViewModel(
            pastureRepository: EmptyPastureRepository(),
            workingRepository: repository
        )
        let savedSessionID = UUID()

        let start = Task {
            try await model.startSession(
                date: .now,
                pastureID: UUID(),
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: nil,
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: {
                    selection.selectionRevision == originatingSelectionRevision
                }
            )
        }
        await repository.waitUntilStarted()

        // A UUID-only check incorrectly treats an obsolete session start as
        // current when the user switches to another Herd and then back.
        selection.select(UUID())
        selection.select(originatingHerdID)
        repository.complete(with: savedSessionID)

        let result = try await start.value
        XCTAssertNil(result)
        XCTAssertEqual(repository.startCallCount, 1)
    }

    func testCompletedSessionStartIsDeliveredWhenHerdRemainsSelected() async throws {
        let originatingHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originatingHerdID)
        let originatingSelectionRevision = selection.selectionRevision
        let repository = SuspendedWorkingSessionStartRepository()
        let model = NewWorkingSessionViewModel(
            pastureRepository: EmptyPastureRepository(),
            workingRepository: repository
        )
        let savedSessionID = UUID()

        let start = Task {
            try await model.startSession(
                date: .now,
                pastureID: UUID(),
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: nil,
                originatingHerdID: originatingHerdID,
                currentHerdSelection: selection,
                selectionIsUnchanged: {
                    selection.selectionRevision == originatingSelectionRevision
                }
            )
        }
        await repository.waitUntilStarted()
        repository.complete(with: savedSessionID)

        let result = try await start.value
        XCTAssertEqual(result, savedSessionID)
        XCTAssertEqual(repository.startCallCount, 1)
    }

    private func makeCandidate(tag: String, pastureID: UUID) -> AnimalSummary {
        AnimalSummary(
            id: UUID(),
            name: "Animal \(tag)",
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
            pastureName: "Test Pasture",
            location: .pasture
        )
    }
}

@MainActor
private final class SuspendedWorkingSessionStartRepository: NewWorkingSessionRepository {
    private(set) var startCallCount = 0
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var pendingCompletion: CheckedContinuation<UUID, Never>?

    func fetchTemplates() throws -> [WorkingTreatmentTemplateSummary] { [] }

    func fetchTemplateDetail(id: UUID) throws -> WorkingTreatmentTemplateDetailSnapshot? { nil }

    func startSession(input: WorkingSessionStartInput) async throws -> UUID {
        startCallCount += 1
        return await withCheckedContinuation { continuation in
            pendingCompletion = continuation
            startedWaiter?.resume()
            startedWaiter = nil
        }
    }

    func waitUntilStarted() async {
        guard startCallCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startedWaiter = continuation
        }
    }

    func complete(with id: UUID) {
        pendingCompletion?.resume(returning: id)
        pendingCompletion = nil
    }
}

private enum WorkingSetupCandidateTestError: Error {
    case pageFailure
}

private actor WorkingSetupCandidateReader: AnimalReferenceQueryReading {
    private let animalsByPasture: [UUID: [AnimalSummary]]
    private let pausedPastureID: UUID?
    private var requests: [UUID: [Int]] = [:]
    private var snapshotRequests: [UUID: Int] = [:]
    private var failureOffset: Int?
    private var pausedRequest: CheckedContinuation<Void, Never>?
    private var pausedRequestEntered: CheckedContinuation<Void, Never>?
    private var hasPausedRequest = false

    init(
        animalsByPasture: [UUID: [AnimalSummary]],
        pausedPastureID: UUID? = nil
    ) {
        self.animalsByPasture = animalsByPasture
        self.pausedPastureID = pausedPastureID
    }

    func setFailureOffset(_ offset: Int?) {
        failureOffset = offset
    }

    func requestedOffsets(for pastureID: UUID) -> [Int] {
        requests[pastureID] ?? []
    }
    func snapshotRequestCount(for pastureID: UUID) -> Int {
        snapshotRequests[pastureID, default: 0]
    }

    func waitForPausedRequest() async {
        if hasPausedRequest { return }
        await withCheckedContinuation { continuation in
            pausedRequestEntered = continuation
        }
    }

    func resumePausedRequest() {
        pausedRequest?.resume()
        pausedRequest = nil
    }

    func fetchAnimalReferencePage(
        matching query: AnimalReferenceQuery,
        page: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        guard case .pasture(let pastureID) = query.pastureScope,
              query.location == .pasture else {
            throw WorkingSetupCandidateTestError.pageFailure
        }

        requests[pastureID, default: []].append(page.offset)
        if pausedPastureID == pastureID && page.offset == 0 {
            await withCheckedContinuation { continuation in
                pausedRequest = continuation
                hasPausedRequest = true
                pausedRequestEntered?.resume()
                pausedRequestEntered = nil
            }
        }
        if failureOffset == page.offset {
            throw WorkingSetupCandidateTestError.pageFailure
        }
        let all = animalsByPasture[pastureID] ?? []
        let animals = Array(all.dropFirst(page.offset).prefix(page.limit))
        return AnimalSummaryPage(
            animals: animals,
            hasMore: page.offset + animals.count < all.count
        )
    }

    func fetchAnimalReferenceSnapshot(
        matching query: AnimalReferenceQuery
    ) async throws -> [AnimalSummary] {
        guard case .pasture(let pastureID) = query.pastureScope,
              query.location == .pasture else {
            throw WorkingSetupCandidateTestError.pageFailure
        }

        snapshotRequests[pastureID, default: 0] += 1
        if pausedPastureID == pastureID {
            await withCheckedContinuation { continuation in
                pausedRequest = continuation
                hasPausedRequest = true
                pausedRequestEntered?.resume()
                pausedRequestEntered = nil
            }
        }
        let all = animalsByPasture[pastureID] ?? []
        // Represents a failed internal hydration chunk inside one snapshot,
        // not multiple independently pinned context generations.
        if let failureOffset,
           failureOffset < all.count {
            throw WorkingSetupCandidateTestError.pageFailure
        }
        return all
    }

    func containsAnimal(id: UUID) async throws -> Bool {
        animalsByPasture.values.contains { animals in
            animals.contains { $0.id == id }
        }
    }
}

@MainActor
private struct WorkingSetupPastureReader: PastureReferenceDataReader {
    let pastureID: UUID
    var shouldFail = false

    func fetchPastureOptions() throws -> [PastureOption] {
        if shouldFail {
            throw WorkingSetupReadError.pastureUnavailable
        }
        return [PastureOption(id: pastureID, name: "Setup Pasture")]
    }
}

@MainActor
private struct WorkingSetupTemplateRepository: NewWorkingSessionRepository {
    var failList = false
    var failDetail = false

    func fetchTemplates() throws -> [WorkingTreatmentTemplateSummary] {
        if failList {
            throw WorkingSetupReadError.templatesUnavailable
        }
        return []
    }

    func fetchTemplateDetail(id: UUID) throws -> WorkingTreatmentTemplateDetailSnapshot? {
        if failDetail {
            throw WorkingSetupReadError.templateDetailUnavailable
        }
        return nil
    }
}

private enum WorkingSetupReadError: LocalizedError {
    case pastureUnavailable
    case templatesUnavailable
    case templateDetailUnavailable

    var errorDescription: String? {
        switch self {
        case .pastureUnavailable: "Test Pasture reference read failed."
        case .templatesUnavailable: "Test Working template list read failed."
        case .templateDetailUnavailable: "Test Working template detail read failed."
        }
    }
}
