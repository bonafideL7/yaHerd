import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class AnimalListViewModelReloadTests: XCTestCase {
    func testReloadSupersedesCancellationInsensitiveInFlightFetch() async {
        let staleAnimal = makeAnimal(name: "Stale animal", tagNumber: "100")
        let freshAnimal = makeAnimal(name: "Fresh animal", tagNumber: "101")
        let queryReader = ControlledAnimalListQueryReader(
            staleAnimal: staleAnimal,
            freshAnimal: freshAnimal
        )
        let repository = BackgroundQueryingAnimalListRepository(
            base: StubAnimalListRepository(),
            queryReader: queryReader
        )
        let pastureRepository = EmptyPastureReferenceDataReader()
        let viewModel = AnimalListViewModel()

        viewModel.load(using: repository, pastureRepository: pastureRepository)

        let firstRequestStarted = await waitForRequestCount(1, reader: queryReader)
        XCTAssertTrue(firstRequestStarted)

        viewModel.load(using: repository, pastureRepository: pastureRepository)

        let replacementRequestStarted = await waitForRequestCount(2, reader: queryReader)
        await queryReader.releaseFirstRequest()

        let freshResultApplied = await waitForAnimal(
            freshAnimal.id,
            in: viewModel
        )
        let requestCount = await queryReader.currentRequestCount()

        XCTAssertTrue(replacementRequestStarted)
        XCTAssertEqual(requestCount, 2)
        XCTAssertTrue(freshResultApplied)
        XCTAssertEqual(viewModel.items, [freshAnimal])
    }

    func testSwitchingHerdWhileReadIsSuspendedDiscardsPriorHerdResult() async {
        let staleAnimal = makeAnimal(name: "Old Herd", tagNumber: "100")
        let currentAnimal = makeAnimal(name: "New Herd", tagNumber: "200")
        let reader = ControlledAnimalListQueryReader(
            staleAnimal: staleAnimal, freshAnimal: currentAnimal
        )
        let repository = BackgroundQueryingAnimalListRepository(
            base: StubAnimalListRepository(), queryReader: reader
        )
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = AnimalListViewModel()
        model.configure(selection: selection)

        model.load(using: repository, pastureRepository: EmptyPastureReferenceDataReader())
        let started = await waitForRequestCount(1, reader: reader)
        XCTAssertTrue(started)

        // Even before SwiftUI's new-Herd task runs, the old request cannot
        // publish a result when its uncooperative reader eventually returns.
        selection.select(UUID())
        await reader.releaseFirstRequest()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(model.pastureOptions.isEmpty)

        model.configure(selection: selection)
        model.load(using: repository, pastureRepository: EmptyPastureReferenceDataReader())
        let loadedCurrentAnimal = await waitForAnimal(currentAnimal.id, in: model)
        XCTAssertTrue(loadedCurrentAnimal)
        XCTAssertEqual(model.items, [currentAnimal])
    }

    func testHerdRoundTripWithoutIntermediateObservationDiscardsStaleRead() async {
        let originalHerdID = UUID()
        let staleAnimal = makeAnimal(name: "Prior selection", tagNumber: "100")
        let freshAnimal = makeAnimal(name: "New selection incarnation", tagNumber: "200")
        let reader = ControlledAnimalListQueryReader(
            staleAnimal: staleAnimal, freshAnimal: freshAnimal
        )
        let repository = BackgroundQueryingAnimalListRepository(
            base: StubAnimalListRepository(), queryReader: reader
        )
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let model = AnimalListViewModel()
        model.configure(selection: selection)
        model.load(using: repository, pastureRepository: EmptyPastureReferenceDataReader())
        let firstRequestStarted = await waitForRequestCount(1, reader: reader)
        XCTAssertTrue(firstRequestStarted)

        // SwiftUI may coalesce both selection updates while the asynchronous
        // reader is suspended. An equal Herd UUID is not the same selection.
        selection.select(UUID())
        selection.select(originalHerdID)
        await reader.releaseFirstRequest()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.errorMessage)

        model.load(using: repository, pastureRepository: EmptyPastureReferenceDataReader())
        let refreshedAnimalLoaded = await waitForAnimal(freshAnimal.id, in: model)
        XCTAssertTrue(refreshedAnimalLoaded)
        XCTAssertEqual(model.items, [freshAnimal])
    }

    func testHerdRoundTripDiscardsErrorFromSupersededRead() async {
        let originalHerdID = UUID()
        let animal = makeAnimal(name: "Current selection", tagNumber: "301")
        let reader = ControlledAnimalListQueryReader(
            staleAnimal: animal, freshAnimal: animal, failFirstRequest: true
        )
        let repository = BackgroundQueryingAnimalListRepository(
            base: StubAnimalListRepository(), queryReader: reader
        )
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let model = AnimalListViewModel()
        model.configure(selection: selection)
        model.load(using: repository, pastureRepository: EmptyPastureReferenceDataReader())
        let started = await waitForRequestCount(1, reader: reader)
        XCTAssertTrue(started)

        selection.select(UUID())
        selection.select(originalHerdID)
        await reader.releaseFirstRequest()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.hasInitialLoadFailure)
        XCTAssertFalse(model.hasLoaded)

        model.load(using: repository, pastureRepository: EmptyPastureReferenceDataReader())
        let loaded = await waitForAnimal(animal.id, in: model)
        XCTAssertTrue(loaded)
        XCTAssertNil(model.errorMessage)
    }

    func testReconfiguringAfterHerdRoundTripResetsPreviouslyLoadedState() {
        let originalHerdID = UUID()
        let animal = makeAnimal(name: "Previously loaded", tagNumber: "401")
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let model = AnimalListViewModel()
        model.configure(selection: selection)
        model.load(
            using: RecordingAnimalListRepository(animals: [animal]),
            pastureRepository: EmptyPastureReferenceDataReader()
        )
        XCTAssertEqual(model.items, [animal])

        selection.select(UUID())
        selection.select(originalHerdID)
        model.configure(selection: selection)

        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(model.pastureOptions.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testFailedPriorHerdReadCannotPublishErrorAfterSelectionChanges() async {
        let staleAnimal = makeAnimal(name: "Old Herd", tagNumber: "101")
        let freshAnimal = makeAnimal(name: "New Herd", tagNumber: "201")
        let reader = ControlledAnimalListQueryReader(
            staleAnimal: staleAnimal,
            freshAnimal: freshAnimal,
            failFirstRequest: true
        )
        let repository = BackgroundQueryingAnimalListRepository(
            base: StubAnimalListRepository(), queryReader: reader
        )
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = AnimalListViewModel()
        model.configure(selection: selection)
        model.load(using: repository, pastureRepository: EmptyPastureReferenceDataReader())
        let started = await waitForRequestCount(1, reader: reader)
        XCTAssertTrue(started)

        selection.select(UUID())
        await reader.releaseFirstRequest()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.hasInitialLoadFailure)

        model.configure(selection: selection)
        model.load(using: repository, pastureRepository: EmptyPastureReferenceDataReader())
        let loadedCurrentAnimal = await waitForAnimal(freshAnimal.id, in: model)
        XCTAssertTrue(loadedCurrentAnimal)
        XCTAssertNil(model.errorMessage)
    }

    func testSwitchingHerdClearsLoadedAndDerivedAnimalState() async {
        let oldAnimal = makeAnimal(name: "Old Herd", tagNumber: "301")
        let newAnimal = makeAnimal(name: "New Herd", tagNumber: "401")
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = AnimalListViewModel()
        model.configure(selection: selection)
        model.updateDerivedState(
            searchText: "",
            sortOrder: .tagAscending,
            filter: AnimalFilter(),
            showRemovedStatuses: false,
            showArchivedRecords: false,
            formatTag: { number, _ in number }
        )
        model.load(
            using: RecordingAnimalListRepository(animals: [oldAnimal]),
            pastureRepository: EmptyPastureReferenceDataReader()
        )
        for _ in 0..<100 {
            if model.hasInitialDerivedState { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.filteredAndSortedAnimals.map(\.id), [oldAnimal.id])

        selection.select(UUID())
        model.configure(selection: selection)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(model.hasInitialDerivedState)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertTrue(model.pastureOptions.isEmpty)
        XCTAssertTrue(model.filteredAndSortedAnimals.isEmpty)
        XCTAssertTrue(model.groupedAnimals.isEmpty)

        model.load(
            using: RecordingAnimalListRepository(animals: [newAnimal]),
            pastureRepository: EmptyPastureReferenceDataReader()
        )
        for _ in 0..<100 {
            if model.filteredAndSortedAnimals.map(\.id) == [newAnimal.id] { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.items.map(\.id), [newAnimal.id])
        XCTAssertEqual(model.filteredAndSortedAnimals.map(\.id), [newAnimal.id])
    }

    func testInitialDerivedEmptyResultsAreNotPublishedBeforeFirstLoad() async {
        let animal = makeAnimal(name: "Loaded animal", tagNumber: "201")
        let snapshotReader = CompleteAnimalListSnapshotProbe(animals: [animal])
        let repository = BackgroundQueryingAnimalListRepository(
            base: StubAnimalListRepository(),
            queryReader: ControlledAnimalListQueryReader(
                staleAnimal: animal,
                freshAnimal: animal
            )
        )
        let model = AnimalListViewModel()

        model.updateDerivedState(
            searchText: "",
            sortOrder: .tagAscending,
            filter: AnimalFilter(),
            showRemovedStatuses: false,
            showArchivedRecords: false,
            formatTag: { number, _ in number }
        )
        for _ in 0..<10 { await Task.yield() }

        XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(model.hasInitialDerivedState)

        model.load(
            using: repository,
            pastureRepository: EmptyPastureReferenceDataReader(),
            snapshotReader: snapshotReader
        )
        for _ in 0..<100 {
            if model.hasInitialDerivedState { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.hasInitialLoadFailure)
        XCTAssertTrue(model.hasInitialDerivedState)
        XCTAssertEqual(model.filteredAndSortedAnimals.map(\.id), [animal.id])
    }

    func testCompleteAnimalListSnapshotIsAtomicAndDoesNotFallBackToIndependentPages() async {
        let records = (0..<525).map {
            makeAnimal(
                name: "Snapshot animal \($0)",
                tagNumber: String(format: "S%04d", $0)
            )
        }
        let snapshotReader = CompleteAnimalListSnapshotProbe(animals: records)
        let pageReader = ControlledAnimalListQueryReader(
            staleAnimal: records[0],
            freshAnimal: records[1]
        )
        let repository = BackgroundQueryingAnimalListRepository(
            base: StubAnimalListRepository(),
            queryReader: pageReader
        )
        let pastureRepository = EmptyPastureReferenceDataReader()
        let model = AnimalListViewModel()

        model.load(
            using: repository,
            pastureRepository: pastureRepository,
            snapshotReader: snapshotReader
        )
        for _ in 0..<100 {
            if model.items.count == records.count { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.items.map(\.id), records.map(\.id))
        let snapshotCalls = await snapshotReader.callCount()
        XCTAssertEqual(snapshotCalls, 1)
        let pageCount = await pageReader.currentRequestCount()
        XCTAssertEqual(pageCount, 0, "Full-list reloads must not issue separately pinned page reads.")

        await snapshotReader.setFailure(true)
        model.load(
            using: repository,
            pastureRepository: pastureRepository,
            snapshotReader: snapshotReader
        )
        for _ in 0..<100 {
            if model.errorMessage != nil { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(
            model.items.map(\.id),
            records.map(\.id),
            "An incomplete/failed reload must not replace the last complete Animal list."
        )

        // Explicit reloads (such as add-sheet dismissal, inline creation and
        // sample-data seeding) use this same load entry point. A successful
        // retry must still fetch a complete snapshot, never independent pages.
        await snapshotReader.setFailure(false)
        model.load(
            using: repository,
            pastureRepository: pastureRepository,
            snapshotReader: snapshotReader
        )
        for _ in 0..<100 {
            if model.errorMessage == nil { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.items.map(\.id), records.map(\.id))
        let requestCount = await snapshotReader.callCount()
        XCTAssertEqual(requestCount, 3)
        let independentPageRequests = await pageReader.currentRequestCount()
        XCTAssertEqual(
            independentPageRequests,
            0,
            "Repeated direct reloads must not regress to independently pinned pages."
        )
    }

    func testHardDeleteRemovesAnimalFromCurrentList() async {
        let animal = makeAnimal(name: "Animal", tagNumber: "103")
        let repository = RecordingAnimalListRepository(animals: [animal])
        let pastureRepository = EmptyPastureReferenceDataReader()
        let viewModel = AnimalListViewModel()

        viewModel.load(using: repository, pastureRepository: pastureRepository)
        XCTAssertEqual(viewModel.items.map(\.id), [animal.id])

        viewModel.performPrimarySwipeAction(
            animalID: animal.id,
            hardDelete: true,
            using: repository,
            pastureRepository: pastureRepository
        )

        XCTAssertEqual(repository.deletedIDs, [animal.id])
        XCTAssertTrue(repository.archivedIDs.isEmpty)
        XCTAssertTrue(viewModel.items.isEmpty)
    }

    func testArchiveSupersedesCancellationInsensitiveInFlightReload() async {
        let animal = makeAnimal(name: "Animal", tagNumber: "102")
        let queryReader = MutationRaceAnimalListQueryReader(animal: animal)
        let repository = BackgroundQueryingAnimalListRepository(
            base: StubAnimalListRepository(),
            queryReader: queryReader
        )
        let pastureRepository = EmptyPastureReferenceDataReader()
        let viewModel = AnimalListViewModel()

        viewModel.load(using: repository, pastureRepository: pastureRepository)
        let initialResultApplied = await waitForAnimal(animal.id, in: viewModel)
        XCTAssertTrue(initialResultApplied)

        viewModel.load(using: repository, pastureRepository: pastureRepository)
        let reloadStarted = await waitForRequestCount(2, reader: queryReader)
        XCTAssertTrue(reloadStarted)

        viewModel.performPrimarySwipeAction(
            animalID: animal.id,
            hardDelete: false,
            using: repository,
            pastureRepository: pastureRepository
        )
        XCTAssertEqual(viewModel.items.first?.isArchived, true)

        await queryReader.releaseReload()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.items.map(\.id), [animal.id])
        XCTAssertEqual(viewModel.items.first?.isArchived, true)
    }

    func testBatchMoveRejectsCallbackAfterHerdSwitch() {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let animal = makeAnimal(name: "Original Herd", tagNumber: "600")
        let repository = RecordingAnimalListRepository(animals: [animal])
        let model = AnimalListViewModel()
        model.configure(selection: selection)
        model.load(using: repository, pastureRepository: EmptyPastureReferenceDataReader())
        let originatingRevision = selection.selectionRevision

        selection.select(UUID())
        model.move(
            ids: [animal.id],
            toPastureID: UUID(),
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: originatingRevision,
            using: repository,
            pastureRepository: EmptyPastureReferenceDataReader()
        )

        XCTAssertTrue(repository.movedIDs.isEmpty)
        XCTAssertEqual(model.items.first?.pastureID, nil)
    }

    func testBatchMoveRejectsHerdRoundTripButAllowsCurrentSelection() {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let animal = makeAnimal(name: "Original Herd", tagNumber: "601")
        let repository = RecordingAnimalListRepository(animals: [animal])
        let model = AnimalListViewModel()
        model.configure(selection: selection)
        model.load(using: repository, pastureRepository: EmptyPastureReferenceDataReader())
        let obsoleteRevision = selection.selectionRevision
        let destination = UUID()

        selection.select(UUID())
        selection.select(originalHerdID)
        model.move(
            ids: [animal.id],
            toPastureID: destination,
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: obsoleteRevision,
            using: repository,
            pastureRepository: EmptyPastureReferenceDataReader()
        )
        XCTAssertTrue(repository.movedIDs.isEmpty)

        model.configure(selection: selection)
        model.move(
            ids: [animal.id],
            toPastureID: destination,
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: selection.selectionRevision,
            using: repository,
            pastureRepository: EmptyPastureReferenceDataReader()
        )
        XCTAssertEqual(repository.movedIDs, [animal.id])
        XCTAssertEqual(repository.movedPastureID, destination)
        XCTAssertEqual(model.items.first?.pastureID, destination)
    }

    private func waitForRequestCount(
        _ expectedCount: Int,
        reader: ControlledAnimalListQueryReader
    ) async -> Bool {
        for _ in 0..<100 {
            if await reader.currentRequestCount() >= expectedCount {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func waitForRequestCount(
        _ expectedCount: Int,
        reader: MutationRaceAnimalListQueryReader
    ) async -> Bool {
        for _ in 0..<100 {
            if await reader.currentRequestCount() >= expectedCount {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func waitForAnimal(
        _ animalID: UUID,
        in viewModel: AnimalListViewModel
    ) async -> Bool {
        for _ in 0..<100 {
            if viewModel.items.map(\.id) == [animalID] {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private func makeAnimal(name: String, tagNumber: String) -> AnimalSummary {
        AnimalSummary(
            id: UUID(),
            name: name,
            displayTagNumber: tagNumber,
            displayTagColorID: nil,
            damDisplayTagNumber: nil,
            damDisplayTagColorID: nil,
            sex: .female,
            animalType: .cow,
            firstDistinguishingFeature: nil,
            birthDate: Date(timeIntervalSince1970: 1_700_000_000),
            status: .active,
            isArchived: false,
            pastureID: nil,
            pastureName: nil,
            location: .pasture
        )
    }
}

private actor ControlledAnimalListQueryReader: AnimalListQueryReading {
    private let staleAnimal: AnimalSummary
    private let freshAnimal: AnimalSummary
    private let failFirstRequest: Bool
    private var requestCount = 0
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?

    init(
        staleAnimal: AnimalSummary,
        freshAnimal: AnimalSummary,
        failFirstRequest: Bool = false
    ) {
        self.staleAnimal = staleAnimal
        self.freshAnimal = freshAnimal
        self.failFirstRequest = failFirstRequest
    }

    func fetchAnimalSummaryPage(
        _ request: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        guard request.offset == 0 else {
            return AnimalSummaryPage(animals: [], hasMore: false)
        }

        requestCount += 1
        if requestCount == 1 {
            await withCheckedContinuation { continuation in
                firstRequestContinuation = continuation
            }
            if failFirstRequest {
                throw CompleteAnimalListSnapshotProbeError.unavailable
            }
            return AnimalSummaryPage(animals: [staleAnimal], hasMore: false)
        }

        return AnimalSummaryPage(animals: [freshAnimal], hasMore: false)
    }

    func fetchAnimalPastureOptions(limit _: Int) async throws -> [PastureOption] {
        []
    }

    func currentRequestCount() -> Int {
        requestCount
    }

    func releaseFirstRequest() {
        firstRequestContinuation?.resume()
        firstRequestContinuation = nil
    }
}

private actor MutationRaceAnimalListQueryReader: AnimalListQueryReading {
    private let animal: AnimalSummary
    private var requestCount = 0
    private var reloadContinuation: CheckedContinuation<Void, Never>?

    init(animal: AnimalSummary) {
        self.animal = animal
    }

    func fetchAnimalSummaryPage(
        _ request: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        guard request.offset == 0 else {
            return AnimalSummaryPage(animals: [], hasMore: false)
        }

        requestCount += 1
        if requestCount == 2 {
            await withCheckedContinuation { continuation in
                reloadContinuation = continuation
            }
        }
        return AnimalSummaryPage(animals: [animal], hasMore: false)
    }

    func fetchAnimalPastureOptions(limit _: Int) async throws -> [PastureOption] {
        []
    }

    func currentRequestCount() -> Int {
        requestCount
    }

    func releaseReload() {
        reloadContinuation?.resume()
        reloadContinuation = nil
    }
}

@MainActor
private final class StubAnimalListRepository: AnimalListRepository {
    func fetchAnimals() throws -> [AnimalSummary] {
        []
    }

    func fetchAnimalDetail(id _: UUID) throws -> AnimalDetailSnapshot? {
        nil
    }

    func create(input _: AnimalInput) throws -> AnimalDetailSnapshot {
        fatalError("Not used by this test.")
    }

    func update(id _: UUID, input _: AnimalInput) throws -> AnimalDetailSnapshot {
        fatalError("Not used by this test.")
    }

    func delete(ids _: [UUID]) throws {}

    func archive(ids _: [UUID]) throws {}

    func restore(ids _: [UUID]) throws {}

    func move(ids _: [UUID], toPastureID _: UUID?) throws {}
}

@MainActor
private final class EmptyPastureReferenceDataReader: PastureReferenceDataReader {
    func fetchPastureOptions() throws -> [PastureOption] {
        []
    }
}


@MainActor
private final class RecordingAnimalListRepository: AnimalListRepository {
    private let animals: [AnimalSummary]
    private(set) var deletedIDs: [UUID] = []
    private(set) var archivedIDs: [UUID] = []
    private(set) var movedIDs: [UUID] = []
    private(set) var movedPastureID: UUID?

    init(animals: [AnimalSummary]) {
        self.animals = animals
    }

    func fetchAnimals() throws -> [AnimalSummary] { animals }
    func fetchAnimalDetail(id _: UUID) throws -> AnimalDetailSnapshot? { nil }
    func create(input _: AnimalInput) throws -> AnimalDetailSnapshot { fatalError("Not used by this test.") }
    func update(id _: UUID, input _: AnimalInput) throws -> AnimalDetailSnapshot { fatalError("Not used by this test.") }
    func delete(ids: [UUID]) throws { deletedIDs.append(contentsOf: ids) }
    func archive(ids: [UUID]) throws { archivedIDs.append(contentsOf: ids) }
    func restore(ids _: [UUID]) throws {}
    func move(ids: [UUID], toPastureID: UUID?) throws {
        movedIDs.append(contentsOf: ids)
        movedPastureID = toPastureID
    }
}


private enum CompleteAnimalListSnapshotProbeError: Error {
    case unavailable
}

private actor CompleteAnimalListSnapshotProbe: AnimalListSnapshotReading {
    let animals: [AnimalSummary]
    private var failing = false
    private var requests = 0

    init(animals: [AnimalSummary]) { self.animals = animals }

    func setFailure(_ value: Bool) { failing = value }
    func callCount() -> Int { requests }

    func fetchAnimalSummarySnapshot() async throws -> [AnimalSummary] {
        requests += 1
        if failing { throw CompleteAnimalListSnapshotProbeError.unavailable }
        return animals
    }
}
