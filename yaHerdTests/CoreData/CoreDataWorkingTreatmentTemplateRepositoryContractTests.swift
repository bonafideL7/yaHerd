@preconcurrency import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataWorkingTreatmentTemplateRepositoryContractTests: XCTestCase {
    func testTreatmentTemplateCRUDAndOrdering() async throws {
        let harness = try await makeHarness()
        try WorkingRepositoryContract.assertTreatmentTemplateCRUDAndOrdering(
            using: harness.fixture
        )
    }

    func testTreatmentTemplatePlanValidationDoesNotPartiallyWrite() async throws {
        let harness = try await makeHarness()
        try WorkingRepositoryContract.assertTreatmentTemplatePlanValidationDoesNotPartiallyWrite(
            using: harness.fixture
        )
    }

    func testTemplateBatchDeletionFailureRollsBackEveryTemplate() async throws {
        let harness = try await makeHarness()
        try WorkingRepositoryContract.assertTemplateBatchDeletionFailureRollsBackEveryTemplate(
            using: harness.fixture,
            failureInjection: harness.failureInjection
        )
    }

    private func makeHarness() async throws -> WorkingTemplateHarness {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = WorkingTemplateCurrentHerdSelection()
        let herdID = UUID()
        selection.currentHerdID = herdID

        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = CDHerd(context: context)
            herd.id = herdID
            herd.name = "Treatment Template Contract Herd"
            herd.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            herd.updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
            try context.save()
        }

        let fixture = WorkingRepositoryContractFixture(
            makeWorkingRepository: {
                CoreDataTemplateWorkingRepositoryAdapter(
                    templates: CoreDataWorkingTreatmentTemplateRepository(
                        selection: selection,
                        assembly: assembly
                    )
                )
            },
            makeAnimalRepository: {
                fatalError("Animal-dependent Working contracts run in Milestone 8.")
            },
            makePastureRepository: {
                fatalError("Pasture-dependent Working contracts run in Milestone 8.")
            },
            makeTagColorRepository: {
                fatalError("Tag-color-dependent Working contracts run in Milestone 8.")
            }
        )

        let failureInjection = WorkingRollbackFailureInjection(
            startSessionFailingAfterQueueStaged: { _ in
                fatalError("Session rollback contracts run in Milestone 8.")
            },
            collectAnimalsFailingAfterQueueStaged: { _, _ in
                fatalError("Session rollback contracts run in Milestone 8.")
            },
            completeQueueItemFailingAfterMutationStaged: { _, _, _, _, _, _ in
                fatalError("Queue rollback contracts run in Milestone 8.")
            },
            replaceWorkDataFailingAfterMutationStaged: { _, _, _ in
                fatalError("Work-data rollback contracts run in Milestone 8.")
            },
            replacePrimaryTagFailingAfterMutationStaged: { _, _, _ in
                fatalError("Tag replacement rollback contracts run in Milestone 8.")
            },
            deleteWorkDataFailingAfterCleanupStaged: { _, _ in
                fatalError("Work-data rollback contracts run in Milestone 8.")
            },
            completeSessionFailingAfterMovementStaged: { _, _ in
                fatalError("Session completion rollback contracts run in Milestone 8.")
            },
            deleteSessionFailingAfterCleanupStaged: { _ in
                fatalError("Session deletion rollback contracts run in Milestone 8.")
            },
            deleteTemplatesFailingAfterDeletionStaged: { ids in
                let repository = CoreDataWorkingTreatmentTemplateRepository(
                    selection: selection,
                    assembly: assembly
                )
                try repository.deleteTemplates(
                    ids: ids,
                    beforeSave: { context in
                        let stagedIDs = Set(
                            context.deletedObjects.compactMap {
                                ($0 as? CDWorkingTreatmentTemplate)?.id
                            }
                        )
                        throw WorkingRollbackInjectedError.afterTemplateDeletionStaged(
                            templateIDs: stagedIDs
                        )
                    }
                )
            },
            persistedQueueItemIDs: {
                fatalError("Queue persistence probes run in Milestone 8.")
            },
            persistedWorkDataIDs: { _, _ in
                fatalError("Work-data persistence probes run in Milestone 8.")
            },
            persistedMovementRecordIDs: { _ in
                fatalError("Movement persistence probes run in Milestone 8.")
            },
            persistedAnimalTagIDs: { _ in
                fatalError("Animal-tag persistence probes run in Milestone 8.")
            },
            persistedTemplateIDs: {
                let context = assembly.contextFactory.makeReadContext()
                return try context.performAndWait {
                    guard let herd = try assembly.lookup.herd(id: herdID, in: context) else {
                        throw HerdRepositoryError.missingHerd
                    }
                    let request = NSFetchRequest<CDWorkingTreatmentTemplate>(
                        entityName: CDWorkingTreatmentTemplate.coreDataEntityName
                    )
                    request.predicate = NSPredicate(format: "herd == %@", herd)
                    return Set(try context.fetch(request).map(\.id))
                }
            }
        )

        return WorkingTemplateHarness(
            fixture: fixture,
            failureInjection: failureInjection
        )
    }
}

@MainActor
private final class WorkingTemplateCurrentHerdSelection: CurrentHerdSelectionReading {
    var currentHerdID: UUID?
}

@MainActor
private struct WorkingTemplateHarness {
    let fixture: WorkingRepositoryContractFixture
    let failureInjection: WorkingRollbackFailureInjection
}

@MainActor
private struct CoreDataTemplateWorkingRepositoryAdapter: WorkingRepository {
    let templates: CoreDataWorkingTreatmentTemplateRepository

    func fetchSessions() throws -> [WorkingSessionSummary] { [] }
    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? { nil }
    func fetchTemplates() throws -> [WorkingTreatmentTemplateSummary] {
        try templates.fetchTemplates()
    }
    func fetchTemplateDetail(id: UUID) throws -> WorkingTreatmentTemplateDetailSnapshot? {
        try templates.fetchTemplateDetail(id: id)
    }
    func fetchQueueItemEditor(
        sessionID: UUID,
        queueItemID: UUID
    ) throws -> WorkingQueueItemEditorSnapshot? { nil }
    func collectAnimals(sessionID: UUID, animalIDs: [UUID]) throws {}
    func complete(
        queueItemID: UUID,
        inSessionID sessionID: UUID,
        treatmentEntries: [WorkingTreatmentEntryInput],
        pregnancyCheck: WorkingPregnancyCheckInput?,
        markCastrated: Bool,
        observationNotes: String
    ) throws {}
    func saveEdits(
        forQueueItemID queueItemID: UUID,
        inSessionID sessionID: UUID,
        input: WorkingSessionAnimalEditInput
    ) throws {}
    func deleteWorkData(forQueueItemID queueItemID: UUID, inSessionID sessionID: UUID) throws {}
    func deleteSession(id: UUID) throws {}
    func completeSession(id: UUID, assignments: [WorkingQueueDestinationAssignment]) throws {}
    func createTemplate(name: String, items: [WorkingTreatmentPlanItem]) throws -> UUID {
        try templates.createTemplate(name: name, items: items)
    }
    func updateTemplate(id: UUID, name: String, items: [WorkingTreatmentPlanItem]) throws {
        try templates.updateTemplate(id: id, name: name, items: items)
    }
    func deleteTemplates(ids: [UUID]) throws {
        try templates.deleteTemplates(ids: ids)
    }
}
