@preconcurrency import CoreData
import Foundation

/// Repository-layer adapter for existing synchronous Domain repository contracts.
///
/// Milestone 3 owns the reusable Core Data persistence foundation. Milestone 4 keeps its
/// synchronous adaptation local to the low-dependency repositories instead of extending the
/// shared transaction executor API.
@MainActor
final class CoreDataSynchronousRepositoryContext {
    private let selection: any CurrentHerdSelectionReading
    private let contextFactory: CoreDataContextFactory
    nonisolated private let lookup: CoreDataLookup

    init(
        selection: any CurrentHerdSelectionReading,
        contextFactory: CoreDataContextFactory,
        lookup: CoreDataLookup
    ) {
        self.selection = selection
        self.contextFactory = contextFactory
        self.lookup = lookup
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup
        )
    }

    func read<Result>(
        _ operation: @Sendable (NSManagedObjectContext, CDHerd) throws -> Result
    ) throws -> Result {
        let herdID = try selectedHerdID()
        let context = contextFactory.makeReadContext()
        let lookup = self.lookup

        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            return try operation(context, herd)
        }
    }

    func write<Result>(
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)? = nil,
        _ operation: @Sendable (NSManagedObjectContext, CDHerd) throws -> Result
    ) throws -> Result {
        let herdID = try selectedHerdID()
        let context = try contextFactory.makeWriteContext()
        let lookup = self.lookup

        return try context.performAndWait {
            do {
                guard let herd = try lookup.herd(id: herdID, in: context) else {
                    throw HerdRepositoryError.missingHerd
                }

                let result = try operation(context, herd)
                guard context.hasChanges else {
                    return result
                }

                try beforeSave?(context)

                do {
                    try context.save()
                    return result
                } catch {
                    context.rollback()
                    throw CoreDataPersistenceError.saveFailed(
                        description: error.localizedDescription
                    )
                }
            } catch {
                if context.hasChanges {
                    context.rollback()
                }
                throw error
            }
        }
    }

    private func selectedHerdID() throws -> UUID {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        return herdID
    }
}
