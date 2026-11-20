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

    /// During two-store CloudKit startup, an empty private store may still be
    /// awaiting import. Select an existing owned root only; never create one
    /// while mirroring is active or accidentally select a shared participant Herd.
    static func resolveExistingPrivateHerdID(
        assembly: CoreDataPersistenceAssembly,
        privateStoreURL: URL
    ) throws -> UUID {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let targetURL = privateStoreURL.standardizedFileURL.resolvingSymlinksInPath()
            guard let privateStore = context.persistentStoreCoordinator?
                .persistentStores.first(where: {
                    $0.url?.standardizedFileURL.resolvingSymlinksInPath() == targetURL
                }) else {
                throw CoreDataPersistenceError.storeLoadFailed(
                    url: privateStoreURL,
                    description: "The owned Herd SQLite store is not loaded."
                )
            }

            let request = NSFetchRequest<CDHerd>(
                entityName: CDHerd.coreDataEntityName
            )
            request.affectedStores = [privateStore]
            let roots = try context.fetch(request)
            switch roots.count {
            case 0:
                throw HerdRepositoryError.missingHerd
            case 1:
                // An import can expose a UUID before its required fields.
                // Never expose an incomplete root as the selected Herd.
                return try roots[0].toSummary().id
            default:
                throw CoreDataAppHerdBootstrapError.multipleLocalHerds(
                    count: roots.count
                )
            }
        }
    }


    /// Discover Herd roots from every loaded store without selecting or creating one.
    /// A partially imported root is not a selectable Herd.
    static func discoverAvailableHerds(
        assembly: CoreDataPersistenceAssembly
    ) throws -> HerdCatalogSnapshot {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let stores = context.persistentStoreCoordinator?.persistentStores,
                  !stores.isEmpty else {
                throw HerdRepositoryError.missingHerd
            }
            var result: [AvailableHerd] = []
            var incompleteRootCount = 0
            var encounteredIDs = Set<UUID>()

            for store in stores {
                let request = NSFetchRequest<CDHerd>(
                    entityName: CDHerd.coreDataEntityName
                )
                request.affectedStores = [store]
                let category: HerdAccessCategory =
                    store.url?.lastPathComponent == CoreDataPersistentContainer.sharedStoreFileName
                    ? .shared : .owned

                for herd in try context.fetch(request) {
                    if let id = herd.id {
                        guard encounteredIDs.insert(id).inserted else {
                            throw CoreDataPersistenceError.duplicateApplicationID(
                                entity: CDHerd.coreDataEntityName,
                                id: id,
                                herdID: nil
                            )
                        }
                    }
                    // CloudKit may import an ID before the rest of its fields.
                    // Do not fabricate defaults or offer an incomplete root.
                    guard let summary = try? herd.toSummary() else {
                        incompleteRootCount += 1
                        continue
                    }
                    result.append(
                        AvailableHerd(id: summary.id, name: summary.name, category: category)
                    )
                }
            }

            result.sort {
                if $0.name != $1.name {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            return HerdCatalogSnapshot(
                herds: result,
                incompleteRootCount: incompleteRootCount
            )
        }
    }

    /// Explicit creation only. Never called merely because the mirrored stores
    /// are empty: an empty device may still be waiting for its CloudKit import.
    static func createOwnedHerd(
        assembly: CoreDataPersistenceAssembly,
        named name: String,
        now: Date = Date()
    ) async throws -> HerdSummary {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HerdRepositoryError.emptyName }

        let context = try assembly.contextFactory.makeWriteContext()
        return try await context.perform {
            do {
                guard let stores = context.persistentStoreCoordinator?.persistentStores,
                      let privateStore = stores.first(where: {
                          $0.url?.lastPathComponent != CoreDataPersistentContainer.sharedStoreFileName
                      }),
                      stores.filter({
                          $0.url?.lastPathComponent != CoreDataPersistentContainer.sharedStoreFileName
                      }).count == 1 else {
                    throw CoreDataPersistenceError.unscopedMultiStoreWrite
                }

                let herd = CDHerd(context: context)
                herd.id = UUID()
                herd.name = trimmed
                herd.createdAt = now
                herd.updatedAt = now
                context.assign(herd, to: privateStore)
                let summary = try herd.toSummary()
                try context.save()
                return summary
            } catch {
                context.rollback()
                throw error
            }
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
            return try context.fetch(request).map { try $0.requiredID() }
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
                return try existing[0].requiredID()
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
            return try herd.requiredID()
        }
    }
}
