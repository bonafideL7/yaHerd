@preconcurrency import CoreData
import Foundation

@MainActor
final class CoreDataHerdRepository: HerdRepository {
    private let selection: any CurrentHerdSelectionReading
    private let contextFactory: CoreDataContextFactory
    private let transactionExecutor: CoreDataTransactionExecutor
    private let lookup: CoreDataLookup

    init(
        selection: any CurrentHerdSelectionReading,
        contextFactory: CoreDataContextFactory,
        transactionExecutor: CoreDataTransactionExecutor,
        lookup: CoreDataLookup
    ) {
        self.selection = selection
        self.contextFactory = contextFactory
        self.transactionExecutor = transactionExecutor
        self.lookup = lookup
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            transactionExecutor: assembly.transactionExecutor,
            lookup: assembly.lookup
        )
    }

    func fetchCurrentHerd() throws -> HerdSummary {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            return try herd.toSummary()
        }
    }


    func availableHerds() throws -> HerdDirectorySnapshot {
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
            let roots = try context.fetch(request)
            var seen = Set<UUID>()
            var complete: [HerdDirectoryEntry] = []
            var incompleteCount = 0

            for root in roots {
                let id = try root.requiredID()
                guard seen.insert(id).inserted else {
                    throw CoreDataPersistenceError.duplicateApplicationID(
                        entity: CDHerd.coreDataEntityName,
                        id: id,
                        herdID: nil
                    )
                }

                do {
                    let summary = try root.toSummary()
                    let location: HerdDirectoryLocation =
                        root.objectID.persistentStore?.url?.lastPathComponent
                            == CoreDataPersistentContainer.sharedStoreFileName
                        ? .shared : .owned
                    complete.append(HerdDirectoryEntry(herd: summary, location: location))
                } catch is CoreDataHerdMappingError {
                    // CloudKit can import the UUID before its name or dates.
                    // Keep this root out of selection but preserve other Herds.
                    incompleteCount += 1
                }
            }

            complete.sort {
                if $0.herd.name != $1.herd.name {
                    return $0.herd.name.localizedStandardCompare($1.herd.name)
                        == .orderedAscending
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            return HerdDirectorySnapshot(
                availableHerds: complete,
                incompleteRootCount: incompleteCount
            )
        }
    }

    /// A new Herd is always an explicit user-owned root. It is assigned to
    /// the private persistent store before saving; the shared store can never
    /// become its destination even when both stores are open.
    func createOwnedHerd(named name: String) async throws -> HerdSummary {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HerdRepositoryError.emptyName }

        let context = try contextFactory.makeWriteContext()
        let createdAt = Date()
        let lookup = self.lookup
        return try await context.perform {
            do {
                guard let stores = context.persistentStoreCoordinator?.persistentStores,
                      !stores.isEmpty else {
                    throw CoreDataPersistenceError.unscopedMultiStoreWrite
                }

                let privateStore: NSPersistentStore
                if stores.count == 1 {
                    privateStore = stores[0]
                } else {
                    guard stores.count == 2,
                          let sharedStore = stores.first(where: {
                              $0.url?.lastPathComponent
                                  == CoreDataPersistentContainer.sharedStoreFileName
                          }),
                          let ownedStore = stores.first(where: { $0 !== sharedStore })
                    else {
                        throw CoreDataPersistenceError.unscopedMultiStoreWrite
                    }
                    privateStore = ownedStore
                }

                let id = UUID()
                guard try lookup.herd(id: id, in: context) == nil else {
                    throw CoreDataPersistenceError.duplicateApplicationID(
                        entity: CDHerd.coreDataEntityName,
                        id: id,
                        herdID: nil
                    )
                }

                let root = CDHerd(context: context)
                root.id = id
                root.name = trimmed
                root.createdAt = createdAt
                root.updatedAt = createdAt
                context.assign(root, to: privateStore)
                try context.save()
                return try root.toSummary()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    func renameCurrentHerd(to name: String) async throws -> HerdSummary {
        try await renameCurrentHerd(to: name, beforeSave: nil)
    }

    func renameCurrentHerd(
        to name: String,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws -> HerdSummary {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw HerdRepositoryError.emptyName
        }
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        let mutationDate = Date()
        let lookup = self.lookup
        return try await transactionExecutor.performWrite(herdID: herdID, beforeSave: beforeSave) { context in
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            // Refuse mutations of incomplete imported Herd roots.
            let previousUpdatedAt = try herd.toSummary().updatedAt
            herd.name = trimmedName
            herd.updatedAt = max(
                mutationDate,
                previousUpdatedAt.addingTimeInterval(0.001)
            )

            return try herd.toSummary()
        }
    }
}
