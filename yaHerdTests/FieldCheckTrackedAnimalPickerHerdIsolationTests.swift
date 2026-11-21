import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class FieldCheckTrackedAnimalPickerHerdIsolationTests: XCTestCase {
    func testInFlightCandidateReadDoesNotPublishAfterHerdSwitch() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let revision = selection.selectionRevision
        let model = FieldCheckTrackedAnimalPickerViewModel()
        let reader = SuspendedFieldCheckAnimalReader()
        let animal = makeAnimal()
        let request = Task { @MainActor in
            await model.load(
                for: makeSession(),
                using: reader,
                selection: selection,
                originatingSelectionRevision: revision
            )
        }

        await reader.awaitReadStarted()
        selection.select(UUID())
        await reader.release(with: [animal])
        await request.value

        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.animals.isEmpty)
        XCTAssertFalse(model.hasCurrentCandidates(
            for: selection, originatingSelectionRevision: revision
        ))
        XCTAssertFalse(model.beginSelectionSubmission(
            selection: selection, originatingSelectionRevision: revision
        ))
    }

    func testQueuedRefreshRejectsPreviousSelectionRevisionEvenAfterHerdRoundTrip() async {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let revision = selection.selectionRevision
        let model = FieldCheckTrackedAnimalPickerViewModel()
        let reader = SuspendedFieldCheckAnimalReader()

        selection.select(UUID())
        selection.select(herdID)
        await model.load(
            for: makeSession(),
            using: reader,
            selection: selection,
            originatingSelectionRevision: revision
        )

        let readCount = await reader.readCount
        XCTAssertEqual(readCount, 0)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.animals.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    func testLoadedCandidatesBecomeInvalidAfterSelectionRoundTrip() async {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let revision = selection.selectionRevision
        let model = FieldCheckTrackedAnimalPickerViewModel()
        let reader = SuspendedFieldCheckAnimalReader()
        let animal = makeAnimal()
        let request = Task { @MainActor in
            await model.load(
                for: makeSession(),
                using: reader,
                selection: selection,
                originatingSelectionRevision: revision
            )
        }

        await reader.awaitReadStarted()
        await reader.release(with: [animal])
        await request.value

        XCTAssertTrue(model.hasCurrentCandidates(
            for: selection, originatingSelectionRevision: revision
        ))
        XCTAssertEqual(model.animals.map(\.id), [animal.id])

        selection.select(UUID())
        selection.select(herdID)

        XCTAssertFalse(model.hasCurrentCandidates(
            for: selection, originatingSelectionRevision: revision
        ))
        XCTAssertFalse(model.beginSelectionSubmission(
            selection: selection, originatingSelectionRevision: revision
        ))
    }

    private func makeSession() -> FieldCheckSessionDetailSnapshot {
        FieldCheckSessionDetailSnapshot(
            id: UUID(),
            startedAt: .now,
            completedAt: nil,
            notes: "",
            pastureID: UUID(),
            pastureName: "Original Pasture",
            expectedHeadCountSnapshot: 1,
            quickCowCount: 0,
            quickHeiferCount: 0,
            quickCalfCount: 0,
            quickBullCount: 0,
            quickSteerCount: 0,
            animalChecks: [],
            findings: []
        )
    }

    private func makeAnimal() -> AnimalSummary {
        AnimalSummary(
            id: UUID(),
            name: "Candidate",
            displayTagNumber: "101",
            displayTagColorID: nil,
            damDisplayTagNumber: nil,
            damDisplayTagColorID: nil,
            sex: .female,
            animalType: .cow,
            firstDistinguishingFeature: nil,
            birthDate: .now,
            status: .active,
            isArchived: false,
            pastureID: nil,
            pastureName: nil,
            location: .pasture
        )
    }
}

private actor SuspendedFieldCheckAnimalReader: AnimalReferenceQueryReading {
    private var pendingRead: CheckedContinuation<[AnimalSummary], Error>?
    private var readStarted: CheckedContinuation<Void, Never>?
    private(set) var readCount = 0

    func awaitReadStarted() async {
        if pendingRead != nil { return }
        await withCheckedContinuation { readStarted = $0 }
    }

    func release(with animals: [AnimalSummary]) {
        pendingRead?.resume(returning: animals)
        pendingRead = nil
    }

    func fetchAnimalReferenceSnapshot(
        matching query: AnimalReferenceQuery
    ) async throws -> [AnimalSummary] {
        readCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pendingRead = continuation
            readStarted?.resume()
            readStarted = nil
        }
    }

    func fetchAnimalReferencePage(
        matching query: AnimalReferenceQuery,
        page: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        AnimalSummaryPage(animals: [], hasMore: false)
    }

    func containsAnimal(id: UUID) async throws -> Bool { false }
}
