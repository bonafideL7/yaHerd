@preconcurrency import CoreData
import Foundation

enum CoreDataAppHerdBootstrapError: LocalizedError, Equatable {
    case multipleLocalHerds(count: Int)

    var errorDescription: String? {
        switch self {
        case .multipleLocalHerds(let count):
            return "The local Core Data store contains \(count) herd roots. yaHerd currently requires exactly one local herd."
        }
    }
}

enum CoreDataAppHerdBootstrapper {
    static let defaultHerdName = "My Herd"

    static func resolveOrCreateCurrentHerdID(
        assembly: CoreDataPersistenceAssembly,
        now: Date = Date()
    ) async throws -> UUID {
        let existingIDs = try fetchHerdIDs(using: assembly.contextFactory)

        switch existingIDs.count {
        case 1:
            return existingIDs[0]

        case 0:
            return try await createInitialHerd(
                assembly: assembly,
                now: now
            )

        default:
            throw CoreDataAppHerdBootstrapError.multipleLocalHerds(
                count: existingIDs.count
            )
        }
    }

    private static func fetchHerdIDs(
        using contextFactory: CoreDataContextFactory
    ) throws -> [UUID] {
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDHerd>(
                entityName: CDHerd.coreDataEntityName
            )
            request.sortDescriptors = [
                NSSortDescriptor(
                    key: "createdAt",
                    ascending: true
                ),
                NSSortDescriptor(
                    key: "id",
                    ascending: true
                )
            ]
            return try context.fetch(request).map(\.id)
        }
    }

    private static func createInitialHerd(
        assembly: CoreDataPersistenceAssembly,
        now: Date
    ) async throws -> UUID {
        try await assembly.transactionExecutor.performWrite { context in
            let request = NSFetchRequest<CDHerd>(
                entityName: CDHerd.coreDataEntityName
            )
            let existing = try context.fetch(request)

            if existing.count == 1 {
                return existing[0].id
            }
            if existing.count > 1 {
                throw CoreDataAppHerdBootstrapError.multipleLocalHerds(
                    count: existing.count
                )
            }

            let herd = CDHerd(context: context)
            herd.id = UUID()
            herd.name = defaultHerdName
            herd.createdAt = now
            herd.updatedAt = now
            return herd.id
        }
    }
}
