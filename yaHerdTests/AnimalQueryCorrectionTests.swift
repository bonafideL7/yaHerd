import XCTest
@testable import yaHerd

final class AnimalQueryCorrectionTests: XCTestCase {
    func testSearchMatchesVisualIdentifierAfterTrimmingWhitespace() {
        let animal = makeAnimal(
            id: UUID(),
            tagNumber: "101",
            name: "",
            visualIdentifier: "White Blaze"
        )

        let result = AnimalQueryEngine.apply(
            to: [animal],
            query: AnimalQuery(searchText: "  blaze  "),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.id), [animal.id])
    }

    func testEqualSortKeysUseStableAnimalIDTieBreaker() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let second = makeAnimal(
            id: secondID,
            tagNumber: "10",
            name: "",
            visualIdentifier: nil
        )
        let first = makeAnimal(
            id: firstID,
            tagNumber: "10",
            name: "",
            visualIdentifier: nil
        )

        let result = AnimalQueryEngine.apply(
            to: [second, first],
            query: AnimalQuery(sortOrder: .tagAscending),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.id), [firstID, secondID])
    }

    private func makeAnimal(
        id: UUID,
        tagNumber: String,
        name: String,
        visualIdentifier: String?
    ) -> AnimalSummary {
        AnimalSummary(
            id: id,
            name: name,
            displayTagNumber: tagNumber,
            displayTagColorID: nil,
            damDisplayTagNumber: nil,
            damDisplayTagColorID: nil,
            sex: .female,
            animalType: .cow,
            firstDistinguishingFeature: visualIdentifier,
            birthDate: Date(timeIntervalSince1970: 0),
            status: .active,
            isArchived: false,
            pastureID: UUID(),
            pastureName: "North",
            location: .pasture
        )
    }
}
