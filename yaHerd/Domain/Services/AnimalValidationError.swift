import Foundation

enum AnimalValidationError: LocalizedError, Equatable {
    case invalidSalePrice
    case animalNotFound
    case animalTagNotFound
    case invalidParentSelection
    case parentSexMismatch(expected: Sex)
    case duplicateParentSelection
    case invalidStatusDate
    case missingStatusDate

    var errorDescription: String? {
        switch self {
        case .invalidSalePrice:
            return "Sale price must be a valid number."
        case .animalNotFound:
            return "That animal could not be found."
        case .animalTagNotFound:
            return "That tag could not be found."
        case .invalidParentSelection:
            return "An animal cannot be assigned as its own parent."
        case .parentSexMismatch(let expected):
            return expected == .male ? "The sire must be male." : "The dam must be female."
        case .duplicateParentSelection:
            return "The sire and dam cannot be the same animal."
        case .invalidStatusDate:
            return "Status dates cannot be earlier than the animal's birth date."
        case .missingStatusDate:
            return "A sold or dead animal must have the corresponding status date."
        }
    }
}
