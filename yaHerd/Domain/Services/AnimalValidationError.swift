import Foundation

enum AnimalValidationError: LocalizedError, Equatable {
    case invalidSalePrice
    case animalNotFound
    case animalTagNotFound

    var errorDescription: String? {
        switch self {
        case .invalidSalePrice:
            return "Sale price must be a valid number."
        case .animalNotFound:
            return "That animal could not be found."
        case .animalTagNotFound:
            return "That tag could not be found."
        }
    }
}
