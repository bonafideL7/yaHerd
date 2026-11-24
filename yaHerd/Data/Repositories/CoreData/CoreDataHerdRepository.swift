@preconcurrency import CoreData
import Foundation
import Synchronization

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

    /// List complete Herd roots from both loaded stores. A partially imported
    /// root cannot safely be selected until its original required fields arrive.
    /// Even incomplete roots participate in UUID collision checks.
    func fetchAccessibleHerds() throws -> [AccessibleHerd] {
        try fetchHerdInventory().herds
    }

    func fetchHerdInventory() throws -> HerdInventory {
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
            request.sortDescriptors = [
                NSSortDescriptor(key: "createdAt", ascending: true),
                NSSortDescriptor(key: "id", ascending: true)
            ]
            let roots = try context.fetch(request)
            let stores = context.persistentStoreCoordinator?.persistentStores ?? []
            var seenIDs = Set<UUID>()
            var available: [AccessibleHerd] = []
            var hasIncompleteRoots = false

            for root in roots {
                // A partially imported root without its UUID must not block
                // valid accessible Herds. Leave it untouched while importing.
                guard let id = root.id else {
                    hasIncompleteRoots = true
                    continue
                }
                guard seenIDs.insert(id).inserted else {
                    throw CoreDataPersistenceError.duplicateApplicationID(
                        entity: CDHerd.coreDataEntityName, id: id, herdID: nil
                    )
                }
                guard let store = root.objectID.persistentStore,
                      stores.contains(where: { $0 === store }) else {
                    throw CoreDataPersistenceError.unresolvedHerdStore(id: id)
                }
                let category: AccessibleHerd.Category
                if stores.count == 1 {
                    category = .owned
                } else if store.url?.lastPathComponent ==
                            CoreDataPersistentContainer.sharedStoreFileName {
                    category = .shared
                } else if store.url?.lastPathComponent ==
                            CoreDataPersistentContainer.storeFileName {
                    category = .owned
                } else {
                    throw CoreDataPersistenceError.unresolvedHerdStore(id: id)
                }

                do {
                    available.append(AccessibleHerd(
                        summary: try root.toSummary(), category: category
                    ))
                } catch let error as CoreDataHerdMappingError {
                    switch error {
                    case .missingName, .missingCreatedAt, .missingUpdatedAt:
                        // Import can deliver the root before its metadata.
                        // Keep the original record untouched and undisplayed.
                        hasIncompleteRoots = true
                        continue
                    case .missingID:
                        throw error
                    }
                }
            }
            return HerdInventory(herds: available, hasIncompleteRoots: hasIncompleteRoots)
        }
    }

    /// Explicit user action. A new owned root belongs only in the private
    /// store; no second default Herd is created by an empty CloudKit import.
    func createOwnedHerd(named name: String) async throws -> HerdSummary {
        try await createOwnedHerd(named: name, beforeSave: nil)
    }

    func createOwnedHerd(
        named name: String,
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws -> HerdSummary {
        try Task.checkCancellation()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw HerdRepositoryError.emptyName
        }

        let context = try contextFactory.makeWriteContext()
        // Swift task cancellation is not automatically visible inside Core
        // Data's private queue. A dismissed chooser must not save its Create.
        let cancellation = Mutex(false)
        return try await withTaskCancellationHandler {
            try await context.perform {
                do {
                    try cancellation.withLock {
                        if $0 { throw CancellationError() }
                    }

                    let stores = context.persistentStoreCoordinator?.persistentStores ?? []
                    let destination: NSPersistentStore
                    if stores.count == 1, let store = stores.first {
                        destination = store
                    } else if stores.count == 2,
                              let privateStore = stores.first(where: {
                                  $0.url?.lastPathComponent ==
                                      CoreDataPersistentContainer.storeFileName
                              }),
                              stores.contains(where: {
                                  $0.url?.lastPathComponent ==
                                      CoreDataPersistentContainer.sharedStoreFileName
                              }) {
                        destination = privateStore
                    } else {
                        throw CoreDataPersistenceError.unscopedMultiStoreWrite
                    }

                    // Do not mistake a partially imported owned root for an
                    // empty private database. Shared roots do not block creation.
                    let existingRequest = NSFetchRequest<CDHerd>(
                        entityName: CDHerd.coreDataEntityName
                    )
                    existingRequest.affectedStores = [destination]
                    for existing in try context.fetch(existingRequest) {
                        do {
                            _ = try existing.toSummary()
                        } catch is CoreDataHerdMappingError {
                            throw HerdRepositoryError.incompleteOwnedHerdImport
                        }
                    }

                    let id = UUID()
                    guard try CoreDataLookup().herd(id: id, in: context) == nil else {
                        throw CoreDataPersistenceError.duplicateApplicationID(
                            entity: CDHerd.coreDataEntityName, id: id, herdID: nil
                        )
                    }

                    let now = Date()
                    let herd = CDHerd(context: context)
                    herd.id = id
                    herd.name = trimmedName
                    herd.createdAt = now
                    herd.updatedAt = now
                    context.assign(herd, to: destination)
                    let summary = try herd.toSummary()
                    try beforeSave?(context)
                    // Respect cancellation after staging but before the commit.
                    // An already-completed save cannot be undone.
                    try cancellation.withLock {
                        if $0 { throw CancellationError() }
                    }
                    do {
                        try context.save()
                    } catch {
                        ReliabilityLog.persistenceSaveFailure("herd-create", error: error)
                        throw CoreDataPersistenceError.saveFailed(
                            description: error.localizedDescription
                        )
                    }
                    return summary
                } catch {
                    if context.hasChanges {
                        context.rollback()
                    }
                    throw error
                }
            }
        } onCancel: {
            cancellation.withLock { $0 = true }
        }
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
