from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}")
    path.write_text(text.replace(old, new, 1))


actions = Path("yaHerd/Presentation/Views/Working/WorkingSessionAnimalWorkView+Actions.swift")
replace_once(
    actions,
    """        let updatedItems = WorkingSessionTreatmentPlanBuilder.items(
            from: treatmentEntries,
            including: entry.id
        )
""",
    """        let updatedItems = WorkingSessionTreatmentPlanBuilder.items(
            preserving: snapshot.plannedTreatments,
            from: treatmentEntries,
            including: entry.id
        )
""",
)
replace_once(
    actions,
    """enum WorkingSessionTreatmentPlanBuilder {
    static func items(
        from entries: [WorkingAnimalTreatmentEntry],
        including entryID: UUID
    ) -> [WorkingTreatmentPlanItem] {
        entries.compactMap { entry in
            guard entry.isPlanned || entry.id == entryID else { return nil }

            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }

            return WorkingTreatmentPlanItem(
                id: entry.id,
                name: name,
                suggestedDose: entry.dose
            )
        }
    }
}
""",
    """enum WorkingSessionTreatmentPlanBuilder {
    static func items(
        preserving existingItems: [WorkingTreatmentPlanItem],
        from entries: [WorkingAnimalTreatmentEntry],
        including entryID: UUID
    ) -> [WorkingTreatmentPlanItem] {
        let existingIDs = Set(existingItems.map(\\.id))
        let locallyPromotedItems = entries.compactMap { entry -> WorkingTreatmentPlanItem? in
            guard entry.isPlanned || entry.id == entryID else { return nil }
            guard !existingIDs.contains(entry.id) else { return nil }

            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }

            return WorkingTreatmentPlanItem(
                id: entry.id,
                name: name,
                suggestedDose: entry.dose
            )
        }

        return existingItems + locallyPromotedItems
    }
}
""",
)

tests = Path("yaHerdTests/WorkingTreatmentPlanReferenceTests.swift")
text = tests.read_text()
old_call = """WorkingSessionTreatmentPlanBuilder.items(
            from: entries,
"""
if text.count(old_call) != 2:
    raise RuntimeError(f"Expected two builder calls in {tests}, found {text.count(old_call)}")
text = text.replace(
    old_call,
    """WorkingSessionTreatmentPlanBuilder.items(
            preserving: [],
            from: entries,
""",
)
old_tail = """        XCTAssertEqual(secondUpdate.map(\\.id), [firstID, secondID])
        XCTAssertEqual(secondUpdate.map(\\.name), [\"First Vaccine\", \"Second Vaccine\"])
    }
}
"""
new_tail = """        XCTAssertEqual(secondUpdate.map(\\.id), [firstID, secondID])
        XCTAssertEqual(secondUpdate.map(\\.name), [\"First Vaccine\", \"Second Vaccine\"])
    }

    func testPromotingOneOffPreservesExistingSessionSuggestedDose() {
        let existingID = UUID()
        let oneOffID = UUID()
        let sessionDose = WorkingTreatmentDose(
            amount: 5,
            unit: .milliliter,
            route: .intramuscular
        )
        let recordedAnimalDose = WorkingTreatmentDose(
            amount: 2,
            unit: .milliliter,
            route: .subcutaneous
        )
        let promotedDose = WorkingTreatmentDose(
            amount: 1.5,
            unit: .cubicCentimeter,
            route: .oral
        )
        let existingItem = WorkingTreatmentPlanItem(
            id: existingID,
            name: \"Session Vaccine\",
            suggestedDose: sessionDose
        )
        let entries = [
            WorkingAnimalTreatmentEntry(
                id: existingID,
                name: \"Session Vaccine\",
                given: true,
                dose: recordedAnimalDose,
                isPlanned: true
            ),
            WorkingAnimalTreatmentEntry(
                id: oneOffID,
                name: \"One-Off Treatment\",
                given: true,
                dose: promotedDose,
                isPlanned: false
            )
        ]

        let updatedItems = WorkingSessionTreatmentPlanBuilder.items(
            preserving: [existingItem],
            from: entries,
            including: oneOffID
        )

        XCTAssertEqual(updatedItems.map(\\.id), [existingID, oneOffID])
        XCTAssertEqual(updatedItems[0].suggestedDose, sessionDose)
        XCTAssertEqual(updatedItems[1].suggestedDose, promotedDose)
    }
}
"""
if old_tail not in text:
    raise RuntimeError(f"Expected test tail not found in {tests}")
tests.write_text(text.replace(old_tail, new_tail, 1))
