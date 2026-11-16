import Foundation

enum HerdAccessCategory: Equatable, Sendable {
    case owned
    case shared
}

struct AvailableHerd: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let category: HerdAccessCategory
}

struct HerdCatalogSnapshot: Equatable, Sendable {
    let herds: [AvailableHerd]
    let incompleteRootCount: Int
}
