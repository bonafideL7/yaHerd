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
