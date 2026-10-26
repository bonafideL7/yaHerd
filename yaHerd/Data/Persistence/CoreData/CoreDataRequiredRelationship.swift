@preconcurrency import CoreData

/// Validates relationships that are logically required even when the CloudKit
/// model makes their storage optional to accommodate out-of-order imports.
enum CoreDataRequiredRelationship {
    static func resolve<Related: NSManagedObject>(
        _ relationship: String,
        from object: NSManagedObject,
        as type: Related.Type
    ) throws -> Related {
        guard let related = object.value(forKey: relationship) as? Related else {
            throw CoreDataPersistenceError.missingRequiredRelationship(
                entity: object.entity.name ?? "Unknown",
                relationship: relationship
            )
        }
        return related
    }
}
