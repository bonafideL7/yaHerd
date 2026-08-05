import XCTest
@testable import yaHerd

final class AnimalQueryPastureSearchTests: XCTestCase {
    func testPastureNameSearchPreservesMandatoryConstraintAndGlobalFilters() {
        let sourcePastureID = UUID()
        let destinationPastureID = UUID()
        let matchingAnimal = makeAnimal(
            tagNumber: "12",
            sex: .female,
            pastureID: sourcePastureID,
            pastureName: "North Field"
        )
        let wrongSex = makeAnimal(
            tagNumber: "13",
            sex: .male,
            pastureID: sourcePastureID,
            pastureName: "North Field"
        )
        let alreadyAtDestination = makeAnimal(
            tagNumber: "14",
            sex: .female,
            pastureID: destinationPastureID,
            pastureName: "North Field"
        )

        let result = AnimalQueryEngine.apply(
            to: [wrongSex, alreadyAtDestination, matchingAnimal],
            query: AnimalQuery(
                searchText: "north",
                filter: AnimalFilter(sex: .female)
            ),
            mandatoryConstraint: { $0.pastureID != destinationPastureID },
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.id), [matchingAnimal.id])
    }

    private func makeAnimal(
        tagNumber: String,
        sex: Sex,
        pastureID: UUID,
        pastureName: String
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
            pastureName: pastureName,
            location: .pasture
        )
    }
}
