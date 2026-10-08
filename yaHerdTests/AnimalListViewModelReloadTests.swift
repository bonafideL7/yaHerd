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
    private var requestCount = 0
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?

    init(staleAnimal: AnimalSummary, freshAnimal: AnimalSummary) {
        self.staleAnimal = staleAnimal
        self.freshAnimal = freshAnimal
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
    func move(ids _: [UUID], toPastureID _: UUID?) throws {}
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
