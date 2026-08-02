import XCTest
@testable import yaHerd

final class FieldCheckAnimalQueryEngineTests: XCTestCase {
    func testSearchMatchesFormattedTagAndDamTag() {
        let whiteID = UUID()
        let matchingTag = makeCheck(tag: "345", colorID: whiteID)
        let matchingDam = makeCheck(tag: "22", damTag: "345", damColorID: whiteID)
        let excluded = makeCheck(tag: "99")

        let result = FieldCheckAnimalQueryEngine.apply(
            to: [excluded, matchingDam, matchingTag],
            query: AnimalQuery(searchText: "W345"),
            formatTag: { number, colorID in
                colorID == whiteID ? "W\(number)" : number
            }
        )

        XCTAssertEqual(Set(result.map(\.id)), Set([matchingTag.id, matchingDam.id]))
    }

    func testSexAndAnimalTypeFiltersCombineWithTagSort() {
        let cow = makeCheck(tag: "12", sex: .female, animalType: .cow)
        let heifer = makeCheck(tag: "3", sex: .female, animalType: .heifer)
        let bull = makeCheck(tag: "2", sex: .male, animalType: .bull)

        let result = FieldCheckAnimalQueryEngine.apply(
            to: [cow, bull, heifer],
            query: AnimalQuery(
                filter: AnimalFilter(sex: .female),
                sortOrder: .tagAscending
            ),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.displayTagNumber), ["3", "12"])
    }

    func testUnavailableHistoricalSortFallsBackToTagOrder() {
        let first = makeCheck(tag: "12")
        let second = makeCheck(tag: "3")

        let result = FieldCheckAnimalQueryEngine.apply(
            to: [first, second],
            query: AnimalQuery(sortOrder: .birthDateNewest),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.displayTagNumber), ["3", "12"])
    }

    func testRosterFilterCombinesWithGlobalAnimalFilter() {
        let remainingFemale = makeCheck(tag: "12", sex: .female)
        let seenFemale = makeCheck(tag: "3", sex: .female, wasCounted: true)
        let remainingMale = makeCheck(tag: "2", sex: .male, animalType: .bull)

        let result = FieldCheckRosterQueryEngine.apply(
            to: [seenFemale, remainingMale, remainingFemale],
            rosterFilter: .remaining,
            effectivelySeenCheckIDs: [],
            query: AnimalQuery(
                filter: AnimalFilter(sex: .female),
                sortOrder: .tagAscending
            ),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.id), [remainingFemale.id])
    }

    func testQuickCountedAnimalIsExcludedFromRemainingRoster() {
        let quickCounted = makeCheck(tag: "3")
        let remaining = makeCheck(tag: "12")

        let result = FieldCheckRosterQueryEngine.apply(
            to: [remaining, quickCounted],
            rosterFilter: .remaining,
            effectivelySeenCheckIDs: [quickCounted.id],
            query: AnimalQuery(),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.id), [remaining.id])
    }

    private func makeCheck(
        tag: String,
        colorID: UUID? = nil,
        damTag: String? = nil,
        damColorID: UUID? = nil,
        sex: Sex = .female,
        animalType: AnimalType = .cow,
        wasExpectedAtStart: Bool = true,
        wasCounted: Bool = false,
        needsAttention: Bool = false,
        isMissing: Bool = false
    ) -> FieldCheckAnimalCheckSnapshot {
        FieldCheckAnimalCheckSnapshot(
            id: UUID(),
            animalID: UUID(),
            displayTagNumber: tag,
            displayTagColorID: colorID,
            damDisplayTagNumber: damTag,
            damDisplayTagColorID: damColorID,
            animalName: "",
            animalSex: sex,
            animalType: animalType,
            wasExpectedAtStart: wasExpectedAtStart,
            wasCounted: wasCounted,
            needsAttention: needsAttention,
            isMissing: isMissing
        )
    }
}
