import XCTest
@testable import yaHerd

@MainActor
final class WorkingCollectAnimalsEligibilityTests: XCTestCase {
    func testExistingSessionAnimalsAreExcludedWhileNewPastureAnimalsRemainAvailable() {
        let sourcePastureID = UUID()
        let existingAnimalID = UUID()
        let newAnimalID = UUID()

        let candidates = WorkingCollectAnimalsEligibility.candidates(
            from: [
                makeAnimalSummary(
                    id: existingAnimalID,
                    displayTagNumber: "12",
                    pastureID: sourcePastureID
                ),
                makeAnimalSummary(
                    id: newAnimalID,
                    displayTagNumber: "34",
                    pastureID: sourcePastureID
                )
            ],
            sourcePastureID: sourcePastureID,
            existingAnimalIDs: [existingAnimalID]
        )

        XCTAssertEqual(candidates.map(\.id), [newAnimalID])
    }


    func testCollectCandidateSnapshotExcludesQueuedIDsAcrossInternalBatches() async throws {
        let sourcePastureID = UUID()
        let otherPastureID = UUID()
        let existing = makeAnimalSummary(id: UUID(), displayTagNumber: "0000", pastureID: sourcePastureID)
        let sourceAnimals = [existing] + (1...505).map {
            makeAnimalSummary(
                id: UUID(),
                displayTagNumber: String(format: "%04d", $0),
                pastureID: sourcePastureID
            )
        }
        let other = makeAnimalSummary(id: UUID(), displayTagNumber: "0999", pastureID: otherPastureID)
        let reader = WorkingCollectReferenceReader(animals: sourceAnimals + [other])
        let session = makeSession(
            sourcePastureID: sourcePastureID,
            existingAnimalID: existing.id
        )

        let animals = try await WorkingCollectAnimalsEligibility.loadCandidates(
            for: session,
            using: reader
        )

        XCTAssertEqual(animals.map(\.id), sourceAnimals.dropFirst().map(\.id))
        XCTAssertFalse(animals.contains { $0.id == existing.id || $0.id == other.id })
        let offsets = await reader.requestedOffsets()
        XCTAssertEqual(offsets, [0, ReadPageRequest.maximumLimit])
        let query = await reader.latestQuery()
        XCTAssertEqual(query?.pastureScope, .pasture(sourcePastureID))
        XCTAssertEqual(query?.location, .pasture)
        XCTAssertTrue(query?.excludedAnimalIDs.contains(existing.id) == true)
    }

    func testCollectSnapshotHydrationFailureDoesNotProducePartialListAndRetries() async throws {
        let pastureID = UUID()
        let candidates = (0..<507).map {
            makeAnimalSummary(
                id: UUID(),
                displayTagNumber: String(format: "%04d", $0),
                pastureID: pastureID
            )
        }
        let reader = WorkingCollectReferenceReader(
            animals: candidates,
            failingOffset: ReadPageRequest.maximumLimit
        )
        let session = makeSession(sourcePastureID: pastureID)

        do {
            _ = try await WorkingCollectAnimalsEligibility.loadCandidates(
                for: session,
                using: reader
            )
            XCTFail("Expected a failed internal snapshot hydration batch.")
        } catch {
            XCTAssertTrue(error is WorkingCollectReferenceReadFailure)
        }
        await reader.setFailureOffset(nil)

        let loaded = try await WorkingCollectAnimalsEligibility.loadCandidates(
            for: session,
            using: reader
        )
        XCTAssertEqual(loaded.map(\.id), candidates.map(\.id))
    }

    func testUnavailableSourcePastureDoesNotFetchOrOfferCandidates() async throws {
        let pastureID = UUID()
        let reader = WorkingCollectReferenceReader(
            animals: [makeAnimalSummary(id: UUID(), displayTagNumber: "10", pastureID: pastureID)]
        )
        let unavailable = WorkingSessionDetailSnapshot(
            id: UUID(),
            date: .now,
            status: .active,
            sourcePastureID: pastureID,
            sourcePastureName: "Deleted source",
            isSourcePastureAvailable: false,
            treatmentTemplateName: "",
            plannedTreatments: [],
            queueItems: []
        )
        let candidates = try await WorkingCollectAnimalsEligibility.loadCandidates(
            for: unavailable,
            using: reader
        )
        XCTAssertTrue(candidates.isEmpty)
        let offsets = await reader.requestedOffsets()
        XCTAssertTrue(offsets.isEmpty)
    }

    private func makeSession(
        sourcePastureID: UUID,
        existingAnimalID: UUID? = nil
    ) -> WorkingSessionDetailSnapshot {
        let queue: [WorkingQueueItemSnapshot]
        if let existingAnimalID {
            queue = [
                WorkingQueueItemSnapshot(
                    id: UUID(),
                    status: .queued,
                    completedAt: nil,
                    animalID: existingAnimalID,
                    animalDisplayTagNumber: "0000",
                    animalDisplayTagColorID: nil,
                    animalDamDisplayTagNumber: nil,
                    animalDamDisplayTagColorID: nil,
                    animalSex: .female,
                    collectedFromPastureName: "North",
                    destinationPastureID: nil,
                    destinationPastureName: nil
                )
            ]
        } else {
            queue = []
        }
        return WorkingSessionDetailSnapshot(
            id: UUID(),
            date: .now,
            status: .active,
            sourcePastureID: sourcePastureID,
            sourcePastureName: "North",
            treatmentTemplateName: "",
            plannedTreatments: [],
            queueItems: queue
        )
    }

    private func makeAnimalSummary(
        id: UUID,
        displayTagNumber: String,
        pastureID: UUID
    ) -> AnimalSummary {
        AnimalSummary(
            id: id,
            name: "Cow \(displayTagNumber)",
            displayTagNumber: displayTagNumber,
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
            pastureName: "North",
            location: .pasture
        )
    }
}

private enum WorkingCollectReferenceReadFailure: Error {
    case failed
}

private actor WorkingCollectReferenceReader: AnimalReferenceQueryReading {
    private let animals: [AnimalSummary]
    private var failingOffset: Int?
    private var offsets: [Int] = []
    private var mostRecentQuery: AnimalReferenceQuery?

    init(animals: [AnimalSummary], failingOffset: Int? = nil) {
        self.animals = animals
        self.failingOffset = failingOffset
    }

    func setFailureOffset(_ offset: Int?) {
        failingOffset = offset
    }

    func requestedOffsets() -> [Int] {
        offsets
    }

    func latestQuery() -> AnimalReferenceQuery? {
        mostRecentQuery
    }

    func fetchAnimalReferencePage(
        matching query: AnimalReferenceQuery,
        page: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        mostRecentQuery = query
        offsets.append(page.offset)
        if page.offset == failingOffset {
            throw WorkingCollectReferenceReadFailure.failed
        }
        guard case .pasture(let sourcePastureID) = query.pastureScope,
              query.location == .pasture else {
            throw WorkingCollectReferenceReadFailure.failed
        }
        let excludedIDs = Set(query.excludedAnimalIDs)
        let candidates = animals
            .filter {
                $0.pastureID == sourcePastureID
                    && $0.location == .pasture
                    && $0.status == .active
                    && !$0.isArchived
                    && !excludedIDs.contains($0.id)
            }
            .sorted {
                $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber)
                    == .orderedAscending
            }
        let selected = Array(candidates.dropFirst(page.offset).prefix(page.limit))
        return AnimalSummaryPage(
            animals: selected,
            hasMore: page.offset + selected.count < candidates.count
        )
    }

    // The test double owns one immutable cohort for the complete request.
    // Simulated internal hydration batches may fail, but no partial cohort escapes.
    func fetchAnimalReferenceSnapshot(
        matching query: AnimalReferenceQuery
    ) async throws -> [AnimalSummary] {
        mostRecentQuery = query
        offsets = []
        guard case .pasture(let sourcePastureID) = query.pastureScope,
              query.location == .pasture else {
            throw WorkingCollectReferenceReadFailure.failed
        }
        let excludedIDs = Set(query.excludedAnimalIDs)
        let candidates = animals
            .filter {
                $0.pastureID == sourcePastureID
                    && $0.location == .pasture
                    && $0.status == .active
                    && !$0.isArchived
                    && !excludedIDs.contains($0.id)
            }
            .sorted {
                $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber)
                    == .orderedAscending
            }
        var results: [AnimalSummary] = []
        for offset in stride(
            from: 0,
            to: max(1, candidates.count),
            by: ReadPageRequest.maximumLimit
        ) {
            offsets.append(offset)
            if failingOffset == offset {
                throw WorkingCollectReferenceReadFailure.failed
            }
            results.append(contentsOf: candidates.dropFirst(offset).prefix(ReadPageRequest.maximumLimit))
        }
        return results
    }

    func containsAnimal(id: UUID) async throws -> Bool {
        animals.contains { $0.id == id }
    }
}
