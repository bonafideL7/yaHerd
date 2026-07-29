import Foundation

enum WorkingTreatmentPlanRules {
    static func validate(_ items: [WorkingTreatmentPlanItem]) throws {
        let ids = items.map(\.id)
        guard Set(ids).count == ids.count else {
            throw WorkingRepositoryError.duplicateTreatmentItemIdentifiers
        }

        guard items.allSatisfy({ item in
            guard let amount = item.suggestedDose.amount else { return true }
            return amount >= 0
        }) else {
            throw WorkingRepositoryError.invalidTreatmentDose
        }
    }

    static func validate(_ entries: [WorkingTreatmentEntryInput]) throws {
        let entryIDs = entries.map(\.treatmentItemID)
        guard Set(entryIDs).count == entryIDs.count else {
            throw WorkingRepositoryError.duplicateTreatmentItemIdentifiers
        }

        guard entries.allSatisfy({ entry in
            guard let amount = entry.dose.amount else { return true }
            return amount >= 0
        }) else {
            throw WorkingRepositoryError.invalidTreatmentDose
        }
    }

    /// Session plans are defaults, not a closed list. An animal may receive a
    /// one-off vaccination or treatment that was not known when the session began.
    static func validate(
        _ entries: [WorkingTreatmentEntryInput],
        against plannedTreatments: [WorkingTreatmentPlanItem]
    ) throws {
        _ = plannedTreatments
        try validate(entries)
    }
}
