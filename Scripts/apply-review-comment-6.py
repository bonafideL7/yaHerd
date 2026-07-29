from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected exactly one match in {path}, found {count}")
    path.write_text(text.replace(old, new, 1))


view_path = Path("yaHerd/Presentation/Views/Working/WorkingSessionAnimalWorkView.swift")
replace_once(
    view_path,
    """        .onChange(of: estimatedDaysText) { _, _ in
            recalculateDueDate()
        }
""",
    "",
)

sections_path = Path("yaHerd/Presentation/Views/Working/WorkingSessionAnimalWorkView+Sections.swift")
replace_once(
    sections_path,
    'TextField("Optional", text: $estimatedDaysText)',
    'TextField("Optional", text: estimatedDaysBinding)',
)

actions_path = Path("yaHerd/Presentation/Views/Working/WorkingSessionAnimalWorkView+Actions.swift")
replace_once(
    actions_path,
    """        recordPregnancyCheck = snapshot.pregnancyCheck != nil
        pregnancyResult = snapshot.pregnancyCheck?.result ?? .unknown
        estimatedDaysText = snapshot.pregnancyCheck?.estimatedDaysPregnant.map { String($0) } ?? ""
        dueDate = snapshot.pregnancyCheck?.dueDate ?? snapshot.sessionDate
        automaticallyCalculatedDueDate = nil
""",
    """        recordPregnancyCheck = snapshot.pregnancyCheck != nil
        pregnancyResult = snapshot.pregnancyCheck?.result ?? .unknown
        let pregnancyDueDateState = WorkingPregnancyDueDateFormState.seeded(
            estimatedDaysPregnant: snapshot.pregnancyCheck?.estimatedDaysPregnant,
            savedDueDate: snapshot.pregnancyCheck?.dueDate,
            fallbackDate: snapshot.sessionDate
        )
        estimatedDaysText = pregnancyDueDateState.estimatedDaysText
        dueDate = pregnancyDueDateState.dueDate
        automaticallyCalculatedDueDate = pregnancyDueDateState.automaticallyCalculatedDueDate
""",
)
replace_once(
    actions_path,
    """    func recalculateDueDate() {
        guard allowsEditing,
              pregnancyResult == .pregnant,
              let snapshot,
              let estimatedDays = Int(
                estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)
              ) else {
            return
        }
""",
    """    var estimatedDaysBinding: Binding<String> {
        Binding(
            get: { estimatedDaysText },
            set: { newValue in
                estimatedDaysText = newValue
                recalculateDueDate(estimatedDaysText: newValue)
            }
        )
    }

    func recalculateDueDate(estimatedDaysText: String) {
        guard allowsEditing,
              pregnancyResult == .pregnant,
              let snapshot,
              let estimatedDays = Int(
                estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)
              ) else {
            return
        }
""",
)
replace_once(
    actions_path,
    """enum WorkingPregnancyDueDateCalculator {
""",
    """struct WorkingPregnancyDueDateFormState: Equatable {
    let estimatedDaysText: String
    let dueDate: Date
    let automaticallyCalculatedDueDate: Date?

    static func seeded(
        estimatedDaysPregnant: Int?,
        savedDueDate: Date?,
        fallbackDate: Date
    ) -> Self {
        Self(
            estimatedDaysText: estimatedDaysPregnant.map(String.init) ?? "",
            dueDate: savedDueDate ?? fallbackDate,
            automaticallyCalculatedDueDate: nil
        )
    }
}

enum WorkingPregnancyDueDateCalculator {
""",
)

test_path = Path("yaHerdTests/WorkingAnimalWorkTimestampTests.swift")
replace_once(
    test_path,
    """    func testManuallyAdjustedDueDateIsPreservedAtSave() throws {
""",
    """    func testSeedingSavedPregnancyCheckPreservesManualDueDate() {
        let savedDueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fallbackDate = Date(timeIntervalSince1970: 1_700_000_000)

        let state = WorkingPregnancyDueDateFormState.seeded(
            estimatedDaysPregnant: 175,
            savedDueDate: savedDueDate,
            fallbackDate: fallbackDate
        )

        XCTAssertEqual(state.estimatedDaysText, "175")
        XCTAssertEqual(state.dueDate, savedDueDate)
        XCTAssertNil(state.automaticallyCalculatedDueDate)
    }

    func testManuallyAdjustedDueDateIsPreservedAtSave() throws {
""",
)
