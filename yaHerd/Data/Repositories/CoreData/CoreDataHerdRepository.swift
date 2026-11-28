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
        guard !contextFactory.herdImportState.blocksHerdAccess else {
            throw HerdRepositoryError.accountUnavailable
        }
        let contextFactory = self.contextFactory
        let context = contextFactory.makeReadContext()
        let inventory = try context.performAndWait {
            let request = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
            request.sortDescriptors = [
                NSSortDescriptor(key: "createdAt", ascending: true),
                NSSortDescriptor(key: "id", ascending: true)
            ]
            let roots = try context.fetch(request)
            let stores = context.persistentStoreCoordinator?.persistentStores ?? []
            // Match metadata by permanent store-qualified object identity, not
            // application UUID. A share-only notification can change this
            // snapshot without changing a Herd row or its history token.
            let sharing = contextFactory.sharingMetadata(for: roots.map(\.objectID))
            let ids = roots.compactMap(\.id)
            let ambiguousIDs = Set(Dictionary(grouping: ids, by: { $0 })
                .filter { $0.value.count > 1 }.keys)
            var available: [AccessibleHerd] = []
            var hasIncompleteRoots = false
            var hasIncompleteOwnedRoots = false

            for root in roots {
                guard let store = root.objectID.persistentStore,
                      stores.contains(where: { $0 === store }) else {
                    if let id = root.id {
                        throw CoreDataPersistenceError.unresolvedHerdStore(id: id)
                    }
                    throw CoreDataPersistenceError.missingApplicationID(entity: CDHerd.coreDataEntityName)
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
                    if let id = root.id {
                        throw CoreDataPersistenceError.unresolvedHerdStore(id: id)
                    }
                    throw CoreDataPersistenceError.missingApplicationID(entity: CDHerd.coreDataEntityName)
                }

                // Ambiguous UUIDs are excluded, not resolved to the first row.
                // Other unambiguous Herds must remain available.
                if let id = root.id, ambiguousIDs.contains(id) {
                    if category == .owned { hasIncompleteOwnedRoots = true }
                    continue
                }

                do {
                    var metadata = sharing[root.objectID] ?? .unavailable
                    if category == .shared {
                        // A cached shared root without its share is not proof
                        // of removal; preserve offline and incomplete imports.
                        if metadata == .noCachedShare { metadata = .unavailable }
                        // Explicit removal from imported metadata is evidence
                        // of lost access even before the root is purged.
                        if metadata.access == .removed { continue }
                    }
                    available.append(AccessibleHerd(
                        summary: try root.toSummary(),
                        category: category,
                        rootIdentity: root.objectID.uriRepresentation(),
                        sharingMetadata: metadata
                    ))
                } catch let error as CoreDataHerdMappingError {
                    switch error {
                    case .missingID, .missingName, .missingCreatedAt, .missingUpdatedAt:
                        // Import can deliver the root before its metadata.
                        // Keep the original record untouched and undisplayed.
                        hasIncompleteRoots = true
                        if category == .owned { hasIncompleteOwnedRoots = true }
                    }
                }
            }
            return HerdInventory(
                herds: available,
                hasIncompleteRoots: hasIncompleteRoots,
                hasIncompleteOwnedRoots: hasIncompleteOwnedRoots,
                ambiguousHerdIDs: ambiguousIDs
            )
        }
        guard !contextFactory.herdImportState.blocksHerdAccess else {
            throw HerdRepositoryError.accountUnavailable
        }
        return inventory
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

        let contextFactory = self.contextFactory
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
                    try contextFactory.authorizeSave(in: context, herdID: nil)
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

        try contextFactory.validateHerdAccess()
        let context = contextFactory.makeReadContext(expectedHerdRoot: selection.selectedRootIdentity)
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
        return try await transactionExecutor.performWrite(
            herdID: herdID, expectedHerdRoot: selection.selectedRootIdentity, beforeSave: beforeSave
        ) { context in
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
