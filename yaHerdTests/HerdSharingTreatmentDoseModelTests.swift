import CoreData
import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class HerdSharingTreatmentDoseModelTests: XCTestCase {
    func testCurrentV1SharingModelUsesStableTreatmentDoseFields() throws {
        let model = HerdSharingCoreDataModelFactory.makeCurrentModel()
        let treatmentEntity = try XCTUnwrap(
            model.entitiesByName[SharedWorkingTreatmentRecord.entityName]
        )

        XCTAssertNotNil(treatmentEntity.propertiesByName["treatmentItemID"])
        XCTAssertNotNil(treatmentEntity.propertiesByName["doseAmount"])
        XCTAssertNotNil(treatmentEntity.propertiesByName["doseUnitRawValue"])
        XCTAssertNotNil(treatmentEntity.propertiesByName["administrationRouteRawValue"])
        XCTAssertNil(treatmentEntity.propertiesByName["quantity"])
        XCTAssertNotNil(
            model.entitiesByName[SharedWorkingSessionRecord.entityName]?
                .propertiesByName["currentQueueIndex"]
        )
        XCTAssertNotNil(
            model.entitiesByName[SharedWorkingQueueItemRecord.entityName]?
                .propertiesByName["queueOrder"]
        )
    }

    func testWorkingSessionBridgeMirrorUsesDoseAndIgnoresQueueOrdering() throws {
        let sharedContext = try makeSharedContext()
        let treatmentItemID = UUID()
        let plannedTreatment = WorkingTreatmentPlanItem(
            id: treatmentItemID,
            name: "Vaccine A",
            suggestedDose: WorkingTreatmentDose(
                amount: 2,
                unit: .milliliter,
                route: .subcutaneous
            )
        )
        let session = WorkingSession(
            protocolName: "Working Session",
            protocolItems: [plannedTreatment]
        )
        session.currentQueueIndex = 14
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        let queueItem = WorkingQueueItem(
            queueOrder: 22,
            status: .done,
            animal: animal,
            session: session
        )
        let treatmentRecord = WorkingTreatmentRecord(
            treatmentItemID: treatmentItemID,
            itemName: plannedTreatment.name,
            given: true,
            dose: WorkingTreatmentDose(
                amount: 2.5,
                unit: .milliliter,
                route: .intramuscular
            ),
            animal: animal,
            session: session
        )

        let sharedSession = SharedWorkingSessionRecord(context: sharedContext)
        sharedSession.mirror(session, herdPublicID: UUID())
        let sharedQueueItem = SharedWorkingQueueItemRecord(context: sharedContext)
        sharedQueueItem.mirror(queueItem, herdPublicID: UUID())
        let sharedTreatment = SharedWorkingTreatmentRecord(context: sharedContext)
        sharedTreatment.mirror(treatmentRecord, herdPublicID: UUID())

        XCTAssertNil(sharedSession.currentQueueIndex)
        XCTAssertNil(sharedQueueItem.queueOrder)
        XCTAssertEqual(sharedTreatment.parsedTreatmentItemID, treatmentItemID)
        XCTAssertEqual(sharedTreatment.parsedDose.amount, 2.5)
        XCTAssertEqual(sharedTreatment.parsedDose.unit, .milliliter)
        XCTAssertEqual(sharedTreatment.parsedDose.route, .intramuscular)
    }

    func testWorkingSessionBridgeImportPreservesDoseAndResetsDeprecatedOrderFields() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let fixtureDate = Date(timeIntervalSince1970: 1_704_067_200)
        let herd = Herd(name: "Bridge Fixture")
        let pasture = Pasture(name: "North")
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        pasture.herd = herd
        animal.herd = herd
        animal.pasture = pasture
        context.insert(herd)
        context.insert(pasture)
        context.insert(animal)
        try context.save()

        let treatmentItemID = UUID()
        let plannedTreatment = WorkingTreatmentPlanItem(
            id: treatmentItemID,
            name: "Vaccine A",
            suggestedDose: WorkingTreatmentDose(
                amount: 2,
                unit: .milliliter,
                route: .subcutaneous
            )
        )
        let sessionID = UUID()
        let queueItemID = UUID()
        let treatmentRecordID = UUID()
        let sharedContext = try makeSharedContext()

        let sharedSession = SharedWorkingSessionRecord(context: sharedContext)
        sharedSession.publicID = sessionID.uuidString
        sharedSession.herdPublicID = herd.publicID.uuidString
        sharedSession.date = fixtureDate
        sharedSession.statusRawValue = WorkingSessionStatus.finished.rawValue
        sharedSession.sourcePasturePublicID = pasture.publicID.uuidString
        sharedSession.protocolName = "Spring Treatments"
        sharedSession.protocolItemsJSON = try JSONEncoder().encode([plannedTreatment])
        sharedSession.currentQueueIndex = NSNumber(value: 91)

        let sharedQueueItem = SharedWorkingQueueItemRecord(context: sharedContext)
        sharedQueueItem.publicID = queueItemID.uuidString
        sharedQueueItem.herdPublicID = herd.publicID.uuidString
        sharedQueueItem.sessionPublicID = sessionID.uuidString
        sharedQueueItem.animalPublicID = animal.publicID.uuidString
        sharedQueueItem.queueOrder = NSNumber(value: 44)
        sharedQueueItem.statusRawValue = WorkingQueueStatus.done.rawValue
        sharedQueueItem.completedAt = fixtureDate
        sharedQueueItem.collectedFromPasturePublicID = pasture.publicID.uuidString
        sharedQueueItem.destinationPasturePublicID = pasture.publicID.uuidString

        let sharedTreatment = SharedWorkingTreatmentRecord(context: sharedContext)
        sharedTreatment.publicID = treatmentRecordID.uuidString
        sharedTreatment.herdPublicID = herd.publicID.uuidString
        sharedTreatment.sessionPublicID = sessionID.uuidString
        sharedTreatment.animalPublicID = animal.publicID.uuidString
        sharedTreatment.date = fixtureDate
        sharedTreatment.treatmentItemID = treatmentItemID.uuidString
        sharedTreatment.itemName = plannedTreatment.name
        sharedTreatment.given = NSNumber(value: true)
        sharedTreatment.doseAmount = NSNumber(value: 2.5)
        sharedTreatment.doseUnitRawValue = WorkingTreatmentDoseUnit.milliliter.rawValue
        sharedTreatment.administrationRouteRawValue =
            WorkingTreatmentAdministrationRoute.intramuscular.rawValue

        let storeDirectory = FileManager.default.temporaryDirectory
            .appending(path: "HerdSharingTreatmentDoseModelTests")
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let store = HerdSharingCoreDataStore(
            storeDirectoryURL: storeDirectory,
            journalFileURL: storeDirectory.appending(path: "journal.json")
        )

        let sessionResult = try store.upsertSwiftDataWorkingSessions(
            from: store.canonicalImportRecords([sharedSession]),
            herd: herd,
            in: context
        )
        try context.save()
        let queueResult = try store.upsertSwiftDataWorkingQueueItems(
            from: store.canonicalImportRecords([sharedQueueItem]),
            herd: herd,
            in: context
        )
        try context.save()
        let treatmentResult = try store.upsertSwiftDataWorkingTreatmentRecords(
            from: store.canonicalImportRecords([sharedTreatment]),
            herd: herd,
            in: context
        )
        try context.save()

        XCTAssertEqual(sessionResult.inserted, 1)
        XCTAssertEqual(queueResult.inserted, 1)
        XCTAssertEqual(treatmentResult.inserted, 1)

        let importedSession = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingSession>())
                .first { $0.publicID == sessionID }
        )
        let importedQueueItem = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingQueueItem>())
                .first { $0.publicID == queueItemID }
        )
        let importedTreatment = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingTreatmentRecord>())
                .first { $0.publicID == treatmentRecordID }
        )

        XCTAssertEqual(importedSession.protocolItems.first?.id, treatmentItemID)
        XCTAssertEqual(importedSession.currentQueueIndex, 0)
        XCTAssertEqual(importedQueueItem.queueOrder, 0)
        XCTAssertEqual(importedQueueItem.session?.publicID, sessionID)
        XCTAssertEqual(importedTreatment.treatmentItemID, treatmentItemID)
        XCTAssertEqual(importedTreatment.doseAmount, 2.5)
        XCTAssertEqual(importedTreatment.doseUnit, .milliliter)
        XCTAssertEqual(importedTreatment.administrationRoute, .intramuscular)
    }

    func testRestoreLocalFieldsRestoresStructuredTreatmentDose() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let animal = Animal(
            name: "Cow 12",
            tagNumber: "12",
            birthDate: .distantPast,
            status: .active,
            sex: .female
        )
        let session = WorkingSession(protocolName: "Working Session", protocolItems: [])
        let treatmentRecordID = UUID()
        let treatmentRecord = WorkingTreatmentRecord(
            publicID: treatmentRecordID,
            treatmentItemID: UUID(),
            itemName: "Vaccine A",
            given: true,
            dose: WorkingTreatmentDose(
                amount: 5,
                unit: .milligram,
                route: .intramuscular
            ),
            animal: animal,
            session: session
        )
        context.insert(animal)
        context.insert(session)
        context.insert(treatmentRecord)
        try context.save()

        let fieldChanges = [
            HerdSharingUpdatedRecordFieldChange(
                fieldName: "doseAmount",
                localValue: .double(2.5),
                sharedValue: .double(5)
            ),
            HerdSharingUpdatedRecordFieldChange(
                fieldName: "doseUnit",
                localValue: .string(WorkingTreatmentDoseUnit.milliliter.rawValue),
                sharedValue: .string(WorkingTreatmentDoseUnit.milligram.rawValue)
            ),
            HerdSharingUpdatedRecordFieldChange(
                fieldName: "administrationRoute",
                localValue: .string(WorkingTreatmentAdministrationRoute.subcutaneous.rawValue),
                sharedValue: .string(WorkingTreatmentAdministrationRoute.intramuscular.rawValue)
            ),
        ]
        let conflict = HerdSharingUpdatedRecordConflict(
            sourceEntityName: SharedWorkingTreatmentRecord.entityName,
            publicID: treatmentRecordID,
            localModifiedAt: Date(timeIntervalSince1970: 10),
            sharedModifiedAt: Date(timeIntervalSince1970: 20),
            fieldChanges: fieldChanges
        )
        let review = HerdSharingConflictReview(
            title: "Shared-data conflicts detected",
            sourceDescription: "Test import",
            detectedAt: Date(timeIntervalSince1970: 30),
            existingLocalRecordUpdateCount: 1,
            updatedRecordConflicts: [conflict],
            preventedDeleteConflicts: []
        )
        let selections = fieldChanges.map {
            HerdSharingLocalFieldRestoreSelection(
                sourceEntityName: SharedWorkingTreatmentRecord.entityName,
                publicID: treatmentRecordID,
                fieldName: $0.fieldName
            )
        }
        let storeDirectory = FileManager.default.temporaryDirectory
            .appending(path: "HerdSharingTreatmentDoseRestoreTests")
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let store = HerdSharingCoreDataStore(
            storeDirectoryURL: storeDirectory,
            journalFileURL: storeDirectory.appending(path: "journal.json")
        )

        let result = try store.restoreLocalFields(
            selections,
            from: review,
            context: context
        )

        XCTAssertEqual(result.requestedFieldCount, 3)
        XCTAssertEqual(result.restoredFieldCount, 3)
        XCTAssertEqual(result.skippedFieldCount, 0)
        XCTAssertEqual(treatmentRecord.doseAmount, 2.5)
        XCTAssertEqual(treatmentRecord.doseUnit, .milliliter)
        XCTAssertEqual(treatmentRecord.administrationRoute, .subcutaneous)
    }

    private func makeSharedContext() throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(
            managedObjectModel: HerdSharingCoreDataModelFactory.makeCurrentModel()
        )
        try coordinator.addPersistentStore(
            ofType: NSInMemoryStoreType,
            configurationName: nil,
            at: nil
        )
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }
}
