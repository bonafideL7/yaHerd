import CoreData
import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class HerdSharingOneOffTreatmentTests: XCTestCase {
    func testBridgeImportsOneOffTreatmentOutsideSessionPlan() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
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

        let sharedContext = try makeSharedContext()
        let sessionID = UUID()
        let treatmentID = UUID()
        let recordID = UUID()

        let sharedSession = SharedWorkingSessionRecord(context: sharedContext)
        sharedSession.publicID = sessionID.uuidString
        sharedSession.herdPublicID = herd.publicID.uuidString
        sharedSession.date = .now
        sharedSession.statusRawValue = WorkingSessionStatus.active.rawValue
        sharedSession.sourcePasturePublicID = pasture.publicID.uuidString
        sharedSession.protocolName = "Working Session"
        sharedSession.protocolItemsJSON = try JSONEncoder().encode([WorkingTreatmentPlanItem]())

        let sharedTreatment = SharedWorkingTreatmentRecord(context: sharedContext)
        sharedTreatment.publicID = recordID.uuidString
        sharedTreatment.herdPublicID = herd.publicID.uuidString
        sharedTreatment.sessionPublicID = sessionID.uuidString
        sharedTreatment.animalPublicID = animal.publicID.uuidString
        sharedTreatment.date = .now
        sharedTreatment.treatmentItemID = treatmentID.uuidString
        sharedTreatment.itemName = "One-Off Antibiotic"
        sharedTreatment.given = NSNumber(value: true)
        sharedTreatment.doseAmount = NSNumber(value: 8)
        sharedTreatment.doseUnitRawValue = WorkingTreatmentDoseUnit.milliliter.rawValue
        sharedTreatment.administrationRouteRawValue =
            WorkingTreatmentAdministrationRoute.intramuscular.rawValue

        let storeDirectory = FileManager.default.temporaryDirectory
            .appending(path: "HerdSharingOneOffTreatmentTests")
            .appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let store = HerdSharingCoreDataStore(
            storeDirectoryURL: storeDirectory,
            journalFileURL: storeDirectory.appending(path: "journal.json")
        )

        _ = try store.upsertSwiftDataWorkingSessions(
            from: store.canonicalImportRecords([sharedSession]),
            herd: herd,
            in: context
        )
        try context.save()
        let result = try store.upsertSwiftDataWorkingTreatmentRecords(
            from: store.canonicalImportRecords([sharedTreatment]),
            herd: herd,
            in: context
        )
        try context.save()

        XCTAssertEqual(result.inserted, 1)
        let imported = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkingTreatmentRecord>())
                .first { $0.publicID == recordID }
        )
        XCTAssertEqual(imported.treatmentItemID, treatmentID)
        XCTAssertEqual(imported.itemName, "One-Off Antibiotic")
        XCTAssertEqual(imported.doseAmount, 8)
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
