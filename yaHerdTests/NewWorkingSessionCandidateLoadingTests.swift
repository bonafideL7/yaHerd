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
        let offsets = await reader.requestedOffsets(for: firstPastureID)
        XCTAssertEqual(offsets, [0, ReadPageRequest.maximumLimit])

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

    func testLaterPageFailureNeverPublishesPartialCandidatesAndAllowsRetry() async {
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

private enum WorkingSetupCandidateTestError: Error {
    case pageFailure
}

private actor WorkingSetupCandidateReader: AnimalReferenceQueryReading {
    private let animalsByPasture: [UUID: [AnimalSummary]]
    private let pausedPastureID: UUID?
    private var requests: [UUID: [Int]] = [:]
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
