import Foundation

enum CoreDataHerdMappingError: Error, Equatable {
    case missingName(herdID: UUID)
    case missingCreatedAt(herdID: UUID)
    case missingUpdatedAt(herdID: UUID)
}

extension CDHerd {
    func toSummary() throws -> HerdSummary {
        // A partially imported Herd must retain its original identity and name.
        // Do not fabricate a display name or permit rename before restoration.
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoreDataHerdMappingError.missingName(herdID: id)
        }
        guard let createdAt else {
            throw CoreDataHerdMappingError.missingCreatedAt(herdID: id)
        }
        guard let updatedAt else {
            throw CoreDataHerdMappingError.missingUpdatedAt(herdID: id)
        }
        return HerdSummary(
            publicID: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
