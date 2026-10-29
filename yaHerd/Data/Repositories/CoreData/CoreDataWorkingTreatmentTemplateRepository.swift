@preconcurrency import CoreData
import Foundation

@MainActor
final class CoreDataWorkingTreatmentTemplateRepository:
    WorkingTreatmentTemplatesRepository,
    WorkingTreatmentTemplateCreating,
    WorkingTreatmentTemplateEditorRepository
{
    private let selection: any CurrentHerdSelectionReading
    private let contextFactory: CoreDataContextFactory
    private let sampleSeedWriteCoordinator: CoreDataSampleSeedWriteCoordinator
    private nonisolated let lookup: CoreDataLookup

    init(
        selection: any CurrentHerdSelectionReading,
        contextFactory: CoreDataContextFactory,
        lookup: CoreDataLookup,
        sampleSeedWriteCoordinator: CoreDataSampleSeedWriteCoordinator
    ) {
        self.selection = selection
        self.contextFactory = contextFactory
        self.lookup = lookup
        self.sampleSeedWriteCoordinator = sampleSeedWriteCoordinator
    }

    convenience init(
        selection: any CurrentHerdSelectionReading,
        assembly: CoreDataPersistenceAssembly
    ) {
        self.init(
            selection: selection,
            contextFactory: assembly.contextFactory,
            lookup: assembly.lookup,
            sampleSeedWriteCoordinator: assembly.sampleSeedWriteCoordinator
        )
    }

    func fetchTemplates() throws -> [WorkingTreatmentTemplateSummary] {
        let (context, herdID) = try makeReadScope()
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            return try Self.fetchTemplates(herd: herd, in: context).map { template in
                let items = try WorkingMapper.treatmentTemplateItems(template)
                return WorkingTreatmentTemplateSummary(
                    id: template.id,
                    name: try WorkingMapper.treatmentTemplateName(template),
                    treatmentCount: items.count
                )
            }
        }
    }

    func fetchTemplateDetail(id: UUID) throws -> WorkingTreatmentTemplateDetailSnapshot? {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        let context = contextFactory.makeReadContext()
        return try context.performAndWait {
            guard try lookup.herd(id: herdID, in: context) != nil else {
                throw HerdRepositoryError.missingHerd
            }
            guard let template = try lookup.herdOwned(
                CDWorkingTreatmentTemplate.self,
                id: id,
                herdID: herdID,
                in: context
            ) else {
                return nil
            }
            return WorkingTreatmentTemplateDetailSnapshot(
                id: template.id,
                name: try WorkingMapper.treatmentTemplateName(template),
                plannedTreatments: try WorkingMapper.treatmentTemplateItems(template)
            )
        }
    }

    @discardableResult
    func createTemplate(name: String, items: [WorkingTreatmentPlanItem]) throws -> UUID {
        try WorkingTreatmentPlanRules.validate(items)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try performWrite { context, herd in
            let newID = try self.uniqueTemplateID(herdID: herd.id, in: context)
            if try Self.templateNameExists(normalizedName, excluding: nil, herd: herd, in: context) {
                throw WorkingRepositoryError.duplicateTemplateName(normalizedName)
            }

            let template = CDWorkingTreatmentTemplate(context: context)
            template.id = newID
            template.name = normalizedName
            template.itemsData = try Self.encodeItems(items)
            template.herd = herd
            return newID
        }
    }

    func updateTemplate(
        id: UUID,
        name: String,
        items: [WorkingTreatmentPlanItem]
    ) throws {
        try WorkingTreatmentPlanRules.validate(items)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        try performWrite { context, herd in
            guard let template = try self.lookup.herdOwned(
                CDWorkingTreatmentTemplate.self,
                id: id,
                herdID: herd.id,
                in: context
            ) else {
                throw WorkingRepositoryError.templateNotFound
            }

            if try Self.templateNameExists(normalizedName, excluding: id, herd: herd, in: context) {
                throw WorkingRepositoryError.duplicateTemplateName(normalizedName)
            }

            template.name = normalizedName
            template.itemsData = try Self.encodeItems(items)
        }
    }

    func deleteTemplates(ids: [UUID]) throws {
        try deleteTemplates(ids: ids, beforeSave: nil)
    }

    func deleteTemplates(
        ids: [UUID],
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) throws {
        guard !ids.isEmpty else { return }
        let requestedIDs = Set(ids)
        try performWrite(beforeSave: beforeSave) { context, herd in
            let templates = try Self.fetchTemplates(herd: herd, in: context)
            let templatesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
            guard requestedIDs.allSatisfy({ templatesByID[$0] != nil }) else {
                throw WorkingRepositoryError.templateNotFound
            }
            for id in requestedIDs {
                if let template = templatesByID[id] {
                    context.delete(template)
                }
            }
        }
    }

    private nonisolated func uniqueTemplateID(
        herdID: UUID,
        in context: NSManagedObjectContext
    ) throws -> UUID {
        while true {
            let id = UUID()
            if try lookup.herdOwned(
                CDWorkingTreatmentTemplate.self,
                id: id,
                herdID: herdID,
                in: context
            ) == nil {
                return id
            }
        }
    }

    private func makeReadScope() throws -> (NSManagedObjectContext, UUID) {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        return (contextFactory.makeReadContext(), herdID)
    }

    private func performWrite<Result: Sendable>(
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)? = nil,
        _ operation: @escaping @Sendable (NSManagedObjectContext, CDHerd) throws -> Result
    ) throws -> Result {
        // One synchronous MainActor entry covers create, update and delete,
        // including their name checks and the physical commit.
        try sampleSeedWriteCoordinator.validateTemplateWriteAvailable()
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        let context = try contextFactory.makeWriteContext()
        return try context.performAndWait {
            do {
                guard let herd = try lookup.herd(id: herdID, in: context) else {
                    throw HerdRepositoryError.missingHerd
                }
                let result = try operation(context, herd)
                if context.hasChanges {
                    try beforeSave?(context)
                    do {
                        try context.save()
                    } catch {
                        context.rollback()
                        throw CoreDataPersistenceError.saveFailed(
                            description: error.localizedDescription
                        )
                    }
                }
                return result
            } catch {
                if context.hasChanges {
                    context.rollback()
                }
                throw error
            }
        }
    }

    private nonisolated static func fetchTemplates(
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> [CDWorkingTreatmentTemplate] {
        let request = NSFetchRequest<CDWorkingTreatmentTemplate>(
            entityName: CDWorkingTreatmentTemplate.coreDataEntityName
        )
        request.predicate = NSPredicate(format: "herd == %@", herd)
        request.sortDescriptors = [
            NSSortDescriptor(key: "name", ascending: true),
            NSSortDescriptor(key: "id", ascending: true)
        ]
        let templates = try context.fetch(request)
        try CoreDataAnimalMutation.validateUniqueApplicationIDs(
            templates,
            herdID: herd.id
        )
        return templates
    }

    private nonisolated static func templateNameExists(
        _ name: String,
        excluding id: UUID?,
        herd: CDHerd,
        in context: NSManagedObjectContext
    ) throws -> Bool {
        try fetchTemplates(herd: herd, in: context).contains { template in
            guard template.id != id else { return false }
            return try WorkingMapper.treatmentTemplateName(template)
                .compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private nonisolated static func encodeItems(_ items: [WorkingTreatmentPlanItem]) throws -> Data {
        try JSONEncoder().encode(items)
    }
}
