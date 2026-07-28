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

    static func validate(
        _ entries: [WorkingTreatmentEntryInput],
        against plannedTreatments: [WorkingTreatmentPlanItem]
    ) throws {
        try validate(entries)

        let plannedIDs = Set(plannedTreatments.map(\.id))
        guard Set(entries.map(\.treatmentItemID)).isSubset(of: plannedIDs) else {
            throw WorkingRepositoryError.treatmentItemNotInSession
        }
    }
}
