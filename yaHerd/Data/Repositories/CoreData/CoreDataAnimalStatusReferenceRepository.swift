@preconcurrency import CoreData
import Foundation

enum CoreDataAnimalStatusReferenceRepositoryError: LocalizedError, Equatable, Sendable {
    case invalidBaseStatus(referenceID: UUID, value: String?)
    case invalidName(referenceID: UUID)

    var errorDescription: String? {
        switch self {
        case .invalidBaseStatus:
            return "The animal status reference contains an invalid persisted base-status value."
        case .invalidName:
            return "The animal status reference has no valid name."
        }
    }
}

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

            try CoreDataAnimalMutation.validateLinkedStatusReferences(herd: herd, in: context)

            let request = NSFetchRequest<CDAnimalStatusReference>(
                entityName: CDAnimalStatusReference.coreDataEntityName
            )
            try lookup.scope(request, toHerd: herd, in: context)
            request.predicate = NSPredicate(format: "herd == %@", herd)
            request.sortDescriptors = [
                NSSortDescriptor(key: "name", ascending: true),
                NSSortDescriptor(key: "id", ascending: true)
            ]

            let references = try context.fetch(request)
            try CoreDataAnimalMutation.validateUniqueApplicationIDs(references, herdID: herd.requiredID())
            return try references.map { reference in
                guard let value = reference.baseStatusRawValue,
                      let baseStatus = AnimalStatus(rawValue: value) else {
                    throw CoreDataAnimalStatusReferenceRepositoryError.invalidBaseStatus(
                        referenceID: (try reference.requiredID()),
                        value: reference.baseStatusRawValue
                    )
                }
                return AnimalStatusReferenceOption(
                    id: (try reference.requiredID()),
                    name: try CoreDataAnimalProjection.statusReferenceName(reference),
                    baseStatus: baseStatus
                )
            }
        }
    }
}
