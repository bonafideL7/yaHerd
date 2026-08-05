import XCTest
@testable import yaHerd

final class AnimalQueryEngineTests: XCTestCase {
    func testSearchMatchesFormattedTag() {
        let whiteID = UUID()
        let animal = makeAnimal(
            tagNumber: "345",
            colorID: whiteID,
            pastureID: UUID()
        )

        let result = AnimalQueryEngine.apply(
            to: [animal],
            query: AnimalQuery(searchText: "W345"),
            formatTag: { number, colorID in
                colorID == whiteID ? "W\(number)" : number
            }
        )

        XCTAssertEqual(result.map(\.id), [animal.id])
    }

    func testMandatoryConstraintIsCombinedWithGlobalQuery() {
        let northID = UUID()
        let southID = UUID()
        let northAnimal = makeAnimal(tagNumber: "101", pastureID: northID)
        let southAnimal = makeAnimal(tagNumber: "102", pastureID: southID)

        let result = AnimalQueryEngine.apply(
            to: [northAnimal, southAnimal],
            query: AnimalQuery(),
            mandatoryConstraint: { $0.pastureID == northID },
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.id), [northAnimal.id])
    }

    func testFiltersAndSortAreAppliedTogether() {
        let first = makeAnimal(tagNumber: "12", sex: .female, pastureID: UUID())
        let second = makeAnimal(tagNumber: "3", sex: .female, pastureID: UUID())
        let excluded = makeAnimal(tagNumber: "99", sex: .male, pastureID: UUID())

        let result = AnimalQueryEngine.apply(
            to: [first, second, excluded],
            query: AnimalQuery(
                filter: AnimalFilter(sex: .female),
                sortOrder: .tagDescending
            ),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.displayTagNumber), ["12", "3"])
    }

    func testWorkingQueueQueryPreservesMissingAnimalsWithoutCriteria() {
        let animal = makeAnimal(tagNumber: "12", pastureID: UUID())
        let animalItem = makeQueueItem(animal: animal)
        let missingItem = makeQueueItem(animal: nil)

        let result = WorkingQueueAnimalQueryEngine.apply(
            to: [missingItem, animalItem],
            summariesByID: [animal.id: animal],
            query: AnimalQuery(),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.id), [animalItem.id, missingItem.id])
    }

    func testWorkingQueueQueryAppliesGlobalFilterWithinSessionMembership() {
        let female = makeAnimal(tagNumber: "12", sex: .female, pastureID: UUID())
        let male = makeAnimal(tagNumber: "3", sex: .male, pastureID: UUID())
        let femaleItem = makeQueueItem(animal: female)
        let maleItem = makeQueueItem(animal: male)

        let result = WorkingQueueAnimalQueryEngine.apply(
            to: [femaleItem, maleItem],
            summariesByID: [
                female.id: female,
                male.id: male
            ],
            query: AnimalQuery(filter: AnimalFilter(sex: .male)),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.id), [maleItem.id])
    }

    private func makeAnimal(
        tagNumber: String,
        colorID: UUID? = nil,
        sex: Sex = .female,
        pastureID: UUID?
    ) -> AnimalSummary {
        AnimalSummary(
            id: UUID(),
            name: "",
            displayTagNumber: tagNumber,
            displayTagColorID: colorID,
            damDisplayTagNumber: nil,
            damDisplayTagColorID: nil,
            sex: sex,
            animalType: .cow,
            firstDistinguishingFeature: nil,
            birthDate: Date(timeIntervalSince1970: 0),
            status: .active,
            isArchived: false,
            pastureID: pastureID,
            pastureName: nil,
            location: .pasture
        )
    }

    private func makeQueueItem(animal: AnimalSummary?) -> WorkingQueueItemSnapshot {
        WorkingQueueItemSnapshot(
            id: UUID(),
            status: .queued,
            completedAt: nil,
            animalID: animal?.id,
            animalDisplayTagNumber: animal?.displayTagNumber,
            animalDisplayTagColorID: animal?.displayTagColorID,
            animalDamDisplayTagNumber: animal?.damDisplayTagNumber,
            animalDamDisplayTagColorID: animal?.damDisplayTagColorID,
            animalSex: animal?.sex ?? .unknown,
            collectedFromPastureName: animal?.pastureName,
            destinationPastureID: nil,
            destinationPastureName: nil
        )
    }
}

@MainActor
final class PastureAnimalQueryTests: XCTestCase {
    func testAnimalSearchReturnsTheContainingPasture() async {
        let north = PastureTestSupport.makeSummary(name: "North")
        let south = PastureTestSupport.makeSummary(name: "South")
        let animal = makeAnimal(tagNumber: "345", pastureID: north.id)
        let viewModel = PastureTileListViewModel()

        await viewModel.load(
            using: PastureListReaderStub(result: .success([north, south])),
            animalQueryReader: AnimalListQueryReaderStub(animals: [animal])
        )

        let matches = viewModel.filteredItems(
            for: .all,
            query: AnimalQuery(searchText: "W345"),
            formatTag: { number, _ in "W\(number)" }
        )

        XCTAssertEqual(matches, [north])
    }

    func testAnimalFilterReturnsPasturesContainingMatchingAnimals() async {
        let north = PastureTestSupport.makeSummary(name: "North")
        let south = PastureTestSupport.makeSummary(name: "South")
        let northCow = makeAnimal(tagNumber: "1", sex: .female, pastureID: north.id)
        let southBull = makeAnimal(tagNumber: "2", sex: .male, pastureID: south.id)
        let viewModel = PastureTileListViewModel()

        await viewModel.load(
            using: PastureListReaderStub(result: .success([north, south])),
            animalQueryReader: AnimalListQueryReaderStub(animals: [northCow, southBull])
        )

        let matches = viewModel.filteredItems(
            for: .all,
            query: AnimalQuery(filter: AnimalFilter(sex: .male)),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(matches, [south])
    }

    private func makeAnimal(
        tagNumber: String,
        sex: Sex = .female,
        pastureID: UUID
    ) -> AnimalSummary {
        AnimalSummary(
            id: UUID(),
            name: "",
            displayTagNumber: tagNumber,
            displayTagColorID: nil,
            damDisplayTagNumber: nil,
            damDisplayTagColorID: nil,
            sex: sex,
            animalType: sex == .male ? .bull : .cow,
            firstDistinguishingFeature: nil,
            birthDate: Date(timeIntervalSince1970: 0),
            status: .active,
            isArchived: false,
            pastureID: pastureID,
            pastureName: nil,
            location: .pasture
        )
    }
}

private struct AnimalListQueryReaderStub: AnimalListQueryReading {
    let animals: [AnimalSummary]

    func fetchAnimalSummaryPage(_ request: ReadPageRequest) async throws -> AnimalSummaryPage {
        let page = Array(animals.dropFirst(request.offset).prefix(request.limit))
        return AnimalSummaryPage(
            animals: page,
            hasMore: request.offset + page.count < animals.count
        )
    }

    func fetchAnimalPastureOptions(limit _: Int) async throws -> [PastureOption] {
        []
    }
}
