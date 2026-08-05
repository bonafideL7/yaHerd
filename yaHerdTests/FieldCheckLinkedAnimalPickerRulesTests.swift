import XCTest
@testable import yaHerd

@MainActor
final class FieldCheckLinkedAnimalPickerRulesTests: XCTestCase {
    func testAnimalOptionsExcludeUnlinkedRosterEntriesAndSortByTag() {
        let unlinked = makeAnimal(tag: "999", animalID: nil)
        let calf = makeAnimal(tag: "C12", name: "Calf")
        let cow = makeAnimal(tag: "101", name: "Daisy")

        let options = FieldCheckLinkedAnimalPickerRules.animalOptions(from: [unlinked, calf, cow])

        XCTAssertEqual(options.map(\.displayTagNumber), ["101", "C12"])
        XCTAssertFalse(options.contains { $0.animalID == nil })
    }

    func testFilterByRosterStatus() {
        let remaining = makeAnimal(tag: "101")
        let missing = makeAnimal(tag: "102", isMissing: true)
        let flagged = makeAnimal(tag: "103", needsAttention: true)
        let checked = makeAnimal(tag: "104", wasCounted: true)
        let added = makeAnimal(tag: "105", wasExpectedAtStart: false, wasCounted: true)
        let animals = [remaining, missing, flagged, checked, added]

        XCTAssertEqual(
            FieldCheckLinkedAnimalPickerRules.filteredAnimals(from: animals, filter: .remaining).map(\.displayTagNumber),
            ["101", "103"]
        )
        XCTAssertEqual(
            FieldCheckLinkedAnimalPickerRules.filteredAnimals(from: animals, filter: .missing).map(\.displayTagNumber),
            ["102"]
        )
        XCTAssertEqual(
            FieldCheckLinkedAnimalPickerRules.filteredAnimals(from: animals, filter: .flagged).map(\.displayTagNumber),
            ["103"]
        )
        XCTAssertEqual(
            FieldCheckLinkedAnimalPickerRules.filteredAnimals(from: animals, filter: .checked).map(\.displayTagNumber),
            ["104", "105"]
        )
        XCTAssertEqual(
            FieldCheckLinkedAnimalPickerRules.filteredAnimals(from: animals, filter: .added).map(\.displayTagNumber),
            ["105"]
        )
    }

    func testPrioritySuggestionsPreferMissingFlaggedThenRemainingAnimals() {
        let checked = makeAnimal(tag: "104", wasCounted: true)
        let remaining = makeAnimal(tag: "103")
        let flagged = makeAnimal(tag: "102", needsAttention: true)
        let missing = makeAnimal(tag: "101", isMissing: true)

        let suggestions = FieldCheckLinkedAnimalPickerRules.priorityAnimals(
            from: [checked, remaining, flagged, missing],
            excluding: nil,
            limit: 3
        )

        XCTAssertEqual(suggestions.map(\.displayTagNumber), ["101", "102", "103"])
    }

    func testPrioritySuggestionsExcludeCurrentSelection() {
        let selectedID = UUID()
        let selected = makeAnimal(tag: "101", animalID: selectedID, isMissing: true)
        let flagged = makeAnimal(tag: "102", needsAttention: true)

        let suggestions = FieldCheckLinkedAnimalPickerRules.priorityAnimals(
            from: [selected, flagged],
            excluding: selectedID,
            limit: 5
        )

        XCTAssertEqual(suggestions.map(\.displayTagNumber), ["102"])
    }

    private func makeAnimal(
        tag: String,
        name: String = "",
        animalID: UUID? = UUID(),
        wasExpectedAtStart: Bool = true,
        wasCounted: Bool = false,
        needsAttention: Bool = false,
        isMissing: Bool = false
    ) -> FieldCheckAnimalCheckSnapshot {
        FieldCheckAnimalCheckSnapshot(
            id: UUID(),
            animalID: animalID,
            displayTagNumber: tag,
            displayTagColorID: nil,
            damDisplayTagNumber: nil,
            damDisplayTagColorID: nil,
            animalName: name,
            animalSex: .female,
            animalType: .cow,
            wasExpectedAtStart: wasExpectedAtStart,
            wasCounted: wasCounted,
            needsAttention: needsAttention,
            isMissing: isMissing
        )
    }
}
