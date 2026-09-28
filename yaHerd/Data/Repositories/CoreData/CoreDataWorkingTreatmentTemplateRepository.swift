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
    private let transactionExecutor: CoreDataTransactionExecutor
    nonisolated private let lookup: CoreDataLookup

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

    func fetchTemplates() throws -> [WorkingTreatmentTemplateSummary] {
        try read { context, herd in
            try self.fetchTemplates(in: context, herd: herd)
                .sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                .map { template in
                    let items = try self.decodeItems(template.itemsData)
                    return WorkingTreatmentTemplateSummary(
                        id: template.id,
                        name: template.name,
                        treatmentCount: items.count
                    )
                }
        }
    }

    func fetchTemplateDetail(id: UUID) throws -> WorkingTreatmentTemplateDetailSnapshot? {
        try read { context, herd in
            guard let template = try self.lookup.herdOwned(
                CDWorkingTreatmentTemplate.self,
                id: id,
                herdID: herd.id,
                in: context
            ) else {
                return nil
            }

            return WorkingTreatmentTemplateDetailSnapshot(
                id: template.id,
                name: template.name,
                plannedTreatments: try self.decodeItems(template.itemsData)
            )
        }
    }

    func createTemplate(
        name: String,
        items: [WorkingTreatmentPlanItem]
    ) async throws -> UUID {
        try WorkingTreatmentPlanRules.validate(items)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        return try await write { context, herd in
            if try self.templateNameExists(
                normalizedName,
                excluding: nil,
                in: context,
                herd: herd
            ) {
                throw WorkingRepositoryError.duplicateTemplateName(normalizedName)
            }

            let template = CDWorkingTreatmentTemplate(context: context)
            template.id = try self.uniqueID(in: context, herdID: herd.id)
            template.name = normalizedName
            template.itemsData = try JSONEncoder().encode(items)
            template.herd = herd
            return template.id
        }
    }

    func updateTemplate(
        id: UUID,
        name: String,
        items: [WorkingTreatmentPlanItem]
    ) async throws {
        try WorkingTreatmentPlanRules.validate(items)
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        try await write { context, herd in
            guard let template = try self.lookup.herdOwned(
                CDWorkingTreatmentTemplate.self,
                id: id,
                herdID: herd.id,
                in: context
            ) else {
                throw WorkingRepositoryError.templateNotFound
            }

            if try self.templateNameExists(
                normalizedName,
                excluding: id,
                in: context,
                herd: herd
            ) {
                throw WorkingRepositoryError.duplicateTemplateName(normalizedName)
            }

            template.name = normalizedName
            template.itemsData = try JSONEncoder().encode(items)
        }
    }

    func deleteTemplates(ids: [UUID]) async throws {
        try await deleteTemplates(ids: ids, beforeSave: nil)
    }

    func deleteTemplates(
        ids: [UUID],
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)?
    ) async throws {
        guard !ids.isEmpty else { return }

        try write(beforeSave: beforeSave) { context, herd in
            let uniqueIDs = ids.reduce(into: [UUID]()) { result, id in
                if !result.contains(id) {
                    result.append(id)
                }
            }

            var templates: [CDWorkingTreatmentTemplate] = []
            templates.reserveCapacity(uniqueIDs.count)
            for id in uniqueIDs {
                guard let template = try self.lookup.herdOwned(
                    CDWorkingTreatmentTemplate.self,
                    id: id,
                    herdID: herd.id,
                    in: context
                ) else {
                    throw WorkingRepositoryError.templateNotFound
                }
                templates.append(template)
            }

            for template in templates {
                context.delete(template)
            }
        }
    }

    private func read<Result>(
        _ operation: @Sendable (NSManagedObjectContext, CDHerd) throws -> Result
    ) throws -> Result {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        let context = contextFactory.makeReadContext()
        let lookup = self.lookup
        return try context.performAndWait {
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            return try operation(context, herd)
        }
    }

    private func write<Result: Sendable>(
        beforeSave: (@Sendable (NSManagedObjectContext) throws -> Void)? = nil,
        _ operation: @escaping @Sendable (NSManagedObjectContext, CDHerd) throws -> Result
    ) async throws -> Result {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }

        let lookup = self.lookup
        return try await transactionExecutor.performWrite(
            beforeSave: beforeSave
        ) { context in
            guard let herd = try lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            return try operation(context, herd)
        }
    }

    private nonisolated func fetchTemplates(
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> [CDWorkingTreatmentTemplate] {
        let request = NSFetchRequest<CDWorkingTreatmentTemplate>(
            entityName: CDWorkingTreatmentTemplate.coreDataEntityName
        )
        request.predicate = NSPredicate(format: "herd == %@", herd)
        return try context.fetch(request)
    }

    private nonisolated func templateNameExists(
        _ name: String,
        excluding id: UUID?,
        in context: NSManagedObjectContext,
        herd: CDHerd
    ) throws -> Bool {
        try fetchTemplates(in: context, herd: herd).contains { template in
            if let id, template.id == id { return false }
            return template.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private nonisolated func uniqueID(
        in context: NSManagedObjectContext,
        herdID: UUID
    ) throws -> UUID {
        var id = UUID()
        while try lookup.herdOwned(
            CDWorkingTreatmentTemplate.self,
            id: id,
            herdID: herdID,
            in: context
        ) != nil {
            id = UUID()
        }
        return id
    }

    private nonisolated func decodeItems(_ data: Data) throws -> [WorkingTreatmentPlanItem] {
        try JSONDecoder().decode([WorkingTreatmentPlanItem].self, from: data)
    }
}
