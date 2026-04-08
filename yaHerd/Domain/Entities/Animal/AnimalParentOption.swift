import Foundation

struct AnimalParentOption: Identifiable, Hashable {
    let id: UUID
    let displayTagNumber: String
    let displayTagColorID: UUID?
    let sex: Sex
    let isArchived: Bool
}
