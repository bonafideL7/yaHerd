import Foundation

struct AnimalParentOption: Identifiable, Hashable {
    let id: UUID
    let name: String
    let displayTagNumber: String
    let displayTagColorID: UUID?
    let sex: Sex
    let isArchived: Bool

    var displayName: String {
        let trimmedTag = displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTag.isEmpty { return trimmedTag }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }

        switch sex {
        case .female:
            return "Untagged dam"
        case .male:
            return "Untagged sire"
        case .unknown:
            return "Untagged animal"
        }
    }
}
