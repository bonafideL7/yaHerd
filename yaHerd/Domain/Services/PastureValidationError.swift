import Foundation

enum PastureValidationError: LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)
    case invalidAcreage
    case invalidUsableAcreage
    case invalidTargetAcresPerHead
    case usableAcreageExceedsAcreage
    case pastureNotFound

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Pasture name can’t be empty."
        case .duplicateName(let name):
            return "A pasture named \(name) already exists. Names must be unique."
        case .invalidAcreage:
            return "Acreage must be greater than zero."
        case .invalidUsableAcreage:
            return "Usable acres must be greater than zero."
        case .invalidTargetAcresPerHead:
            return "Target acres per head must be greater than zero."
        case .usableAcreageExceedsAcreage:
            return "Usable acres can’t exceed total acreage."
        case .pastureNotFound:
            return "That pasture could not be found."
        }
    }
}
