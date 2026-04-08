import Foundation

struct AnimalStatusReferenceOption: Identifiable, Hashable {
    let id: UUID
    let name: String
    let baseStatus: AnimalStatus
}
