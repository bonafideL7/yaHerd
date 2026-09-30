import Foundation

struct AnimalTagInput: Hashable, Sendable {
    let number: String
    let colorID: UUID?
    let isPrimary: Bool
}
