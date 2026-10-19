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

    func testSearchMatchesDamTagStatusAndType() {
        let calf = makeAnimal(
            tag: "C12",
            name: "",
            damTag: "D55",
            animalType: .calf,
            isMissing: true
        )
        let cow = makeAnimal(tag: "101", name: "Daisy", animalType: .cow)

        let damMatches = FieldCheckLinkedAnimalPickerRules.filteredAnimals(
            from: [calf, cow],
            searchText: "D55",
            filter: .all
        )
        let statusMatches = FieldCheckLinkedAnimalPickerRules.filteredAnimals(
            from: [calf, cow],
            searchText: "missing",
            filter: .all
        )
        let typeMatches = FieldCheckLinkedAnimalPickerRules.filteredAnimals(
            from: [calf, cow],
            searchText: "calf",
            filter: .all
        )

        XCTAssertEqual(damMatches.map(\.displayTagNumber), ["C12"])
        XCTAssertEqual(statusMatches.map(\.displayTagNumber), ["C12"])
        XCTAssertEqual(typeMatches.map(\.displayTagNumber), ["C12"])
    }

    func testFilterByRosterStatus() {
        let remaining = makeAnimal(tag: "101")
        let missing = makeAnimal(tag: "102", isMissing: true)
        let flagged = makeAnimal(tag: "103", needsAttention: true)
        let checked = makeAnimal(tag: "104", wasCounted: true)
        let added = makeAnimal(tag: "105", wasExpectedAtStart: false, wasCounted: true)
        let animals = [remaining, missing, flagged, checked, added]

        XCTAssertEqual(
            FieldCheckLinkedAnimalPickerRules.filteredAnimals(from: animals, searchText: "", filter: .remaining).map(\.displayTagNumber),
            ["101", "103"]
        )
        XCTAssertEqual(
            FieldCheckLinkedAnimalPickerRules.filteredAnimals(from: animals, searchText: "", filter: .missing).map(\.displayTagNumber),
            ["102"]
        )
        XCTAssertEqual(
            FieldCheckLinkedAnimalPickerRules.filteredAnimals(from: animals, searchText: "", filter: .flagged).map(\.displayTagNumber),
            ["103"]
        )
        XCTAssertEqual(
            FieldCheckLinkedAnimalPickerRules.filteredAnimals(from: animals, searchText: "", filter: .checked).map(\.displayTagNumber),
            ["104", "105"]
        )
        XCTAssertEqual(
            FieldCheckLinkedAnimalPickerRules.filteredAnimals(from: animals, searchText: "", filter: .added).map(\.displayTagNumber),
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
        damTag: String? = nil,
        animalType: AnimalType = .cow,
        sex: Sex = .female,
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
            damDisplayTagNumber: damTag,
            damDisplayTagColorID: nil,
            animalName: name,
            animalSex: sex,
            animalType: animalType,
            wasExpectedAtStart: wasExpectedAtStart,
            wasCounted: wasCounted,
            needsAttention: needsAttention,
            isMissing: isMissing
        )
    }
}
