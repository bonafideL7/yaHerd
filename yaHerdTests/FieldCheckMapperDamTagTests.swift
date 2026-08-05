import XCTest
@testable import yaHerd

final class FieldCheckMapperDamTagTests: XCTestCase {
    func testBlankDamSnapshotRemainsAbsentDuringUntaggedSearch() {
        let check = FieldCheckAnimalCheck(
            rosterTagNumber: "12",
            damRosterTagNumber: "   "
        )
        let snapshot = FieldCheckMapper.makeAnimalCheckSnapshot(
            from: check,
            needsAttention: false
        )

        XCTAssertNil(snapshot.damDisplayTagNumber)

        let result = FieldCheckAnimalQueryEngine.apply(
            to: [snapshot],
            query: AnimalQuery(searchText: "UT"),
            formatTag: { number, _ in
                number.isEmpty ? "UT" : number
            }
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testExplicitUntaggedDamSnapshotStillMatchesUntaggedSearch() {
        let check = FieldCheckAnimalCheck(
            rosterTagNumber: "12",
            damRosterTagNumber: "UT"
        )
        let snapshot = FieldCheckMapper.makeAnimalCheckSnapshot(
            from: check,
            needsAttention: false
        )

        XCTAssertEqual(snapshot.damDisplayTagNumber, "UT")

        let result = FieldCheckAnimalQueryEngine.apply(
            to: [snapshot],
            query: AnimalQuery(searchText: "UT"),
            formatTag: { number, _ in number }
        )

        XCTAssertEqual(result.map(\.id), [snapshot.id])
    }
}
