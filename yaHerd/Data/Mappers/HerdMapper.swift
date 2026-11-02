import Foundation

enum CoreDataHerdMappingError: Error, Equatable {
    case missingCreatedAt(herdID: UUID)
    case missingUpdatedAt(herdID: UUID)
}

extension CDHerd {
    func toSummary() throws -> HerdSummary {
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
