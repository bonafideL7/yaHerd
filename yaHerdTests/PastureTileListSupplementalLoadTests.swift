import XCTest
@testable import yaHerd

@MainActor
final class PastureTileListSupplementalLoadTests: XCTestCase {
    func testLoadPublishesPasturesBeforeSupplementalAnimalFetchCompletes() async {
        let north = PastureTestSupport.makeSummary(name: "North")
        let repository = PastureListReaderStub(result: .success([north]))
        let animalQueryReader = SuspendedFailingAnimalQueryReader()
        let viewModel = PastureTileListViewModel()

        let loadTask = Task {
            await viewModel.load(
                using: repository,
                animalQueryReader: animalQueryReader
            )
        }

        let animalFetchStarted = await waitForAnimalFetchStart(animalQueryReader)

        XCTAssertTrue(animalFetchStarted)
        XCTAssertEqual(viewModel.items, [north])
        XCTAssertTrue(viewModel.residentAnimalsByPastureID.isEmpty)
        XCTAssertNil(viewModel.errorMessage)

        await animalQueryReader.resumeWithFailure()
        await loadTask.value

        XCTAssertEqual(viewModel.items, [north])
        XCTAssertTrue(viewModel.residentAnimalsByPastureID.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    private func waitForAnimalFetchStart(
        _ reader: SuspendedFailingAnimalQueryReader
    ) async -> Bool {
        for _ in 0..<100 {
            if await reader.hasStarted {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private actor SuspendedFailingAnimalQueryReader: AnimalListQueryReading {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasStarted = false

    func fetchAnimalSummaryPage(
        _ request: ReadPageRequest
    ) async throws -> AnimalSummaryPage {
        hasStarted = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        throw SupplementalAnimalQueryTestError.failed
    }

    func fetchAnimalPastureOptions(limit _: Int) async throws -> [PastureOption] {
        []
    }

    func resumeWithFailure() {
        continuation?.resume()
        continuation = nil
    }
}

private enum SupplementalAnimalQueryTestError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Supplemental animal query failed."
    }
}
