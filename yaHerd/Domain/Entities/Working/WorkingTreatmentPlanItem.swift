import Foundation

/// A treatment planned for a working session or reusable treatment template.
/// `id` is persisted with the session/template and is the stable identity used by
/// per-animal treatment records, even when the treatment name changes.
struct WorkingTreatmentPlanItem: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var suggestedDose: WorkingTreatmentDose = WorkingTreatmentDose()

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case suggestedDose
        case defaultQuantity
    }

    init(
        id: UUID = UUID(),
        name: String,
        suggestedDose: WorkingTreatmentDose = WorkingTreatmentDose()
    ) {
        self.id = id
        self.name = name
        self.suggestedDose = suggestedDose
    }

    /// Decodes both the current treatment-plan payload and the pre-structured-dose
    /// payload that stored an optional `defaultQuantity` directly on the item.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""

        if let dose = try container.decodeIfPresent(WorkingTreatmentDose.self, forKey: .suggestedDose) {
            suggestedDose = dose
        } else {
            let legacyQuantity = try container.decodeIfPresent(Double.self, forKey: .defaultQuantity)
            suggestedDose = WorkingTreatmentDose(amount: legacyQuantity)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(suggestedDose, forKey: .suggestedDose)
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
