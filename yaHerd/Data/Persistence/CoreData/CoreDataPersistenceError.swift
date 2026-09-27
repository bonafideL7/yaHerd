import Foundation

enum CoreDataPersistenceError: LocalizedError, Equatable {
    case modelNotFound(name: String)
    case storeLoadFailed(url: URL?, description: String)
    case saveFailed(description: String)
    case duplicateApplicationID(entity: String, id: UUID, herdID: UUID?)
    case readOnlyStore

    var errorDescription: String? {
        switch self {
        case let .modelNotFound(name):
            return "The Core Data model \(name) could not be found."
        case let .storeLoadFailed(url, description):
            let location = url?.path ?? "<in-memory>"
            return "The Core Data store at \(location) could not be loaded: \(description)"
        case let .saveFailed(description):
            return "The Core Data transaction could not be saved: \(description)"
        case let .duplicateApplicationID(entity, id, herdID):
            if let herdID {
                return "More than one \(entity) has application UUID \(id.uuidString) in Herd \(herdID.uuidString)."
            }
            return "More than one \(entity) has store-global application UUID \(id.uuidString)."
        case .readOnlyStore:
            return "Changes are disabled while the Core Data store is read-only."
        }
    }
}
