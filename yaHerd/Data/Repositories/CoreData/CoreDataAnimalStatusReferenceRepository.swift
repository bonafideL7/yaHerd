@preconcurrency import CoreData
import Foundation

@MainActor
final class CoreDataAnimalStatusReferenceRepository: AnimalStatusReferenceReading {
    private let selection: any CurrentHerdSelectionReading
    private let contextFactory: CoreDataContextFactory
    private let lookup: CoreDataLookup

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

    func fetchStatusReferenceOptions() throws -> [AnimalStatusReferenceOption] {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            let request = NSFetchRequest<CDAnimalStatusReference>(
                entityName: CDAnimalStatusReference.coreDataEntityName
            )
            request.predicate = NSPredicate(format: "herd == %@", herd)
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

            return try context.fetch(request).map { reference in
                AnimalStatusReferenceOption(
                    id: reference.id,
                    name: reference.name,
                    baseStatus: AnimalStatus(rawValue: reference.baseStatusRawValue) ?? .active
                )
            }
        }
    }
}
