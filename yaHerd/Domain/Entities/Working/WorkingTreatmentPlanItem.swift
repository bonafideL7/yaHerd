import Foundation

/// A treatment planned for a working session or reusable treatment template.
/// `id` is persisted with the session/template and is the stable identity used by
/// per-animal treatment records, even when the treatment name changes.
struct WorkingTreatmentPlanItem: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String = ""
    var suggestedDose: WorkingTreatmentDose = WorkingTreatmentDose()

    init(
        id: UUID = UUID(),
        name: String,
        suggestedDose: WorkingTreatmentDose = WorkingTreatmentDose()
    ) {
        self.id = id
        self.name = name
        self.suggestedDose = suggestedDose
    }

    /// Transitional V1 source compatibility. New code uses `suggestedDose`.
    init(id: UUID = UUID(), name: String, defaultQuantity: Double?) {
        self.init(
            id: id,
            name: name,
            suggestedDose: WorkingTreatmentDose(amount: defaultQuantity)
        )
    }

    /// Transitional V1 source compatibility. New code uses `suggestedDose`.
    var defaultQuantity: Double? {
        get { suggestedDose.amount }
        set { suggestedDose.amount = newValue }
    }
}
