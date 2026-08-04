import XCTest
@testable import yaHerd

final class WorkingQueueAnimalQueryVisibilityTests: XCTestCase {
    func testInclusionOnlyQueriesPreserveMissingAnimalRows() {
        let animal = makeAnimal(tagNumber: "12")
        let animalItem = makeQueueItem(animal: animal)
        let missingItem = makeQueueItem(animal: nil)
        let queries = [
            AnimalQuery(showRemovedStatuses: true),
            AnimalQuery(showArchivedRecords: true),
            AnimalQuery(showRemovedStatuses: true, showArchivedRecords: true)
        ]

        for query in queries {
            let result = WorkingQueueAnimalQueryEngine.apply(
                to: [missingItem, animalItem],
                summariesByID: [animal.id: animal],
                query: query,
                formatTag: { number, _ in number }
            )

            XCTAssertEqual(result.map(\.id), [animalItem.id, missingItem.id])
        }
    }

    func testNarrowingQueryStillRemovesMissingAnimalRows() {
        let matchingAnimal = makeAnimal(tagNumber: "12")
        let excludedAnimal = makeAnimal(tagNumber: "34")
        let matchingItem = makeQueueItem(animal: matchingAnimal)
        let excludedItem = makeQueueItem(animal: excludedAnimal)
        let missingItem = makeQueueItem(animal: nil)

        let result = WorkingQueueAnimalQueryEngine.apply(
            to: [missingItem, excludedItem, matchingItem],
            summariesByID: [
                matchingAnimal.id: matchingAnimal,
                excludedAnimal.id: excludedAnimal
            ],
            query: AnimalQuery(searchText: "12", showRemovedStatuses: true),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.id), [matchingItem.id])
    }

    func testSearchMatchesDestinationPastureName() {
        let matchingAnimal = makeAnimal(tagNumber: "12")
        let excludedAnimal = makeAnimal(tagNumber: "34")
        let matchingItem = makeQueueItem(
            animal: matchingAnimal,
            destinationPastureName: "North Holding"
        )
        let excludedItem = makeQueueItem(
            animal: excludedAnimal,
            destinationPastureName: "South Pasture"
        )

        let result = WorkingQueueAnimalQueryEngine.apply(
            to: [excludedItem, matchingItem],
            summariesByID: [
                matchingAnimal.id: matchingAnimal,
                excludedAnimal.id: excludedAnimal
            ],
            query: AnimalQuery(searchText: "holding"),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.id), [matchingItem.id])
    }

    func testDestinationSearchStillHonorsGlobalAnimalFilter() {
        let femaleAnimal = makeAnimal(tagNumber: "12", sex: .female)
        let maleAnimal = makeAnimal(tagNumber: "34", sex: .male)
        let femaleItem = makeQueueItem(
            animal: femaleAnimal,
            destinationPastureName: "North Holding"
        )
        let maleItem = makeQueueItem(
            animal: maleAnimal,
            destinationPastureName: "North Holding"
        )

        let result = WorkingQueueAnimalQueryEngine.apply(
            to: [maleItem, femaleItem],
            summariesByID: [
                femaleAnimal.id: femaleAnimal,
                maleAnimal.id: maleAnimal
            ],
            query: AnimalQuery(
                searchText: "North",
                filter: AnimalFilter(sex: .female)
            ),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.id), [femaleItem.id])
    }

    func testEqualSortKeysPreserveSessionSourceOrder() {
        let animals = (0..<6).map { _ in makeAnimal(tagNumber: "12") }
        let items = animals.map { makeQueueItem(animal: $0) }
        let summariesByID = Dictionary(
            uniqueKeysWithValues: animals.map { ($0.id, $0) }
        )
        let sourceOrders = [items, Array(items.reversed())]

        for sourceItems in sourceOrders {
            let result = WorkingQueueAnimalQueryEngine.apply(
                to: sourceItems,
                summariesByID: summariesByID,
                query: AnimalQuery(sortOrder: .tagAscending),
                formatTag: { number, _ in number }
            )

            XCTAssertEqual(result.map(\.id), sourceItems.map(\.id))
        }
    }

    private func makeAnimal(
        tagNumber: String,
        sex: Sex = .female
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
            pastureID: UUID(),
            pastureName: nil,
            location: .pasture
        )
    }

    private func makeQueueItem(
        animal: AnimalSummary?,
        destinationPastureName: String? = nil
    ) -> WorkingQueueItemSnapshot {
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
            destinationPastureName: destinationPastureName
        )
    }
}
