import CoreData
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class PublicIDRepairBridgeDuplicateRecordRegressionTests: XCTestCase {
    func testDuplicateBridgeAnimalsAreMappedToBothRepairedIDsAndSurviveConvergence() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeStoreDirectory() }

        let local = try makeAnimalGraph(
            herdID: fixture.herdID,
            retainedAnimalID: fixture.retainedAnimalID,
            replacementAnimalID: fixture.replacementAnimalID,
            retainedName: "Alpha",
            replacementName: "Beta"
        )
        let bridgeSource = try makeAnimalGraph(
            herdID: fixture.herdID,
            retainedAnimalID: fixture.retainedAnimalID,
            replacementAnimalID: fixture.replacementAnimalID,
            retainedName: "Alpha",
            replacementName: "Beta"
        )
        let bridgeActor = SwiftDataHerdSharingActor(modelContainer: bridgeSource.container)
        let seedExport = try await bridgeActor.makeExport(
            for: bridgeSource.herd.toSummary(),
            storeDescription: "duplicate-bridge-seed"
        )
        _ = try await fixture.store.writeBridgeSnapshot(
            seedExport.snapshot,
            to: fixture.privateStore
        )
        try corruptReplacementBridgeAnimalID(
            in: fixture,
            replacementID: fixture.replacementAnimalID,
            retainedID: fixture.retainedAnimalID
        )

        let contaminated = try await fixture.store.readBridgeSnapshot(
            from: fixture.privateStore,
            requestedHerdPublicID: fixture.herdID,
            storeDescription: "duplicate-bridge-contaminated"
        )
        XCTAssertEqual(contaminated.records(for: .animals).count, 2)
        XCTAssertEqual(
            Set(contaminated.records(for: .animals).compactMap(\.parsedPublicID)),
            [fixture.retainedAnimalID]
        )

        let localActor = SwiftDataHerdSharingActor(modelContainer: local.container)
        let report = makeRepairReport(fixture: fixture)
        _ = try await fixture.store.importPublicIDRepairBridgeRecordsIntoSwiftData(
            for: local.herd.toSummary(),
            expectedLocation: .ownerPrivateStore,
            expectedFingerprint: contaminated.publicIDRepairFingerprint,
            importer: localActor,
            report: report
        )

        let postImportAnimals = try ModelContext(local.container).fetch(FetchDescriptor<Animal>())
        XCTAssertEqual(postImportAnimals.count, 2)
        XCTAssertEqual(
            Set(postImportAnimals.map(\.publicID)),
            [fixture.retainedAnimalID, fixture.replacementAnimalID]
        )
        XCTAssertEqual(Set(postImportAnimals.map(\.name)), ["Alpha", "Beta"])

        let postImportHerd = try XCTUnwrap(
            ModelContext(local.container).fetch(FetchDescriptor<Herd>()).first
        )
        let repairedExport = try await localActor.makeExport(
            for: postImportHerd.toSummary(),
            storeDescription: "duplicate-bridge-convergence"
        )
        let convergence = try await fixture.store.syncPublicIDRepairBridgeRecordsFromSnapshot(
            repairedExport,
            expectedLocation: .ownerPrivateStore,
            expectedFingerprint: contaminated.publicIDRepairFingerprint
        )
        XCTAssertFalse(convergence.reconciliationReport.hasUnresolvedDifferences)

        let converged = try await fixture.store.readBridgeSnapshot(
            from: fixture.privateStore,
            requestedHerdPublicID: fixture.herdID,
            storeDescription: "duplicate-bridge-converged"
        )
        XCTAssertEqual(converged.records(for: .animals).count, 2)
        XCTAssertEqual(
            Set(converged.records(for: .animals).compactMap(\.parsedPublicID)),
            [fixture.retainedAnimalID, fixture.replacementAnimalID]
        )
        XCTAssertEqual(
            Set(converged.records(for: .animals).compactMap { record in
                guard case .string(let name) = record.attributes["name"] else { return nil }
                return name
            }),
            ["Alpha", "Beta"]
        )
    }

    func testDuplicateBridgeAnimalsWithoutPortableOneToOneMappingFailClosed() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeStoreDirectory() }

        let local = try makeAnimalGraph(
            herdID: fixture.herdID,
            retainedAnimalID: fixture.retainedAnimalID,
            replacementAnimalID: fixture.replacementAnimalID,
            retainedName: "Alpha",
            replacementName: "Beta"
        )
        let bridgeSource = try makeAnimalGraph(
            herdID: fixture.herdID,
            retainedAnimalID: fixture.retainedAnimalID,
            replacementAnimalID: fixture.replacementAnimalID,
            retainedName: "Alpha",
            replacementName: "Alpha",
            useSameAnimalDetails: true
        )
        let bridgeActor = SwiftDataHerdSharingActor(modelContainer: bridgeSource.container)
        let seedExport = try await bridgeActor.makeExport(
            for: bridgeSource.herd.toSummary(),
            storeDescription: "ambiguous-duplicate-bridge-seed"
        )
        _ = try await fixture.store.writeBridgeSnapshot(
            seedExport.snapshot,
            to: fixture.privateStore
        )
        try corruptReplacementBridgeAnimalID(
            in: fixture,
            replacementID: fixture.replacementAnimalID,
            retainedID: fixture.retainedAnimalID
        )

        let contaminated = try await fixture.store.readBridgeSnapshot(
            from: fixture.privateStore,
            requestedHerdPublicID: fixture.herdID,
            storeDescription: "ambiguous-duplicate-bridge"
        )
        let localActor = SwiftDataHerdSharingActor(modelContainer: local.container)

        do {
            _ = try await fixture.store.importPublicIDRepairBridgeRecordsIntoSwiftData(
                for: local.herd.toSummary(),
                expectedLocation: .ownerPrivateStore,
                expectedFingerprint: contaminated.publicIDRepairFingerprint,
                importer: localActor,
                report: makeRepairReport(fixture: fixture)
            )
            XCTFail("Expected ambiguous duplicate bridge mapping to remain blocked")
        } catch let error as HerdSharingActionError {
            guard case .bridgeConsistencyFailed(let message) = error else {
                return XCTFail("Unexpected sharing error: \(error)")
            }
            XCTAssertTrue(message.contains("portable fields"))
        }

        let animals = try ModelContext(local.container).fetch(FetchDescriptor<Animal>())
        XCTAssertEqual(animals.count, 2)
        XCTAssertEqual(
            Set(animals.map(\.publicID)),
            [fixture.retainedAnimalID, fixture.replacementAnimalID]
        )
    }

    func testRetainedDuplicateGroupTombstoneFailsClosedWithoutDeletingCanonicalAnimal() async throws {
        try await verifyAmbiguousTombstoneFailsClosed(targetsReplacementID: false)
    }

    func testReplacementDuplicateGroupTombstoneFailsClosedWithoutDeletingRepairedAnimal() async throws {
        try await verifyAmbiguousTombstoneFailsClosed(targetsReplacementID: true)
    }

    private func verifyAmbiguousTombstoneFailsClosed(
        targetsReplacementID: Bool
    ) async throws {
        let fixture = try makeFixture()
        defer { fixture.removeStoreDirectory() }
        let local = try makeAnimalGraph(
            herdID: fixture.herdID,
            retainedAnimalID: fixture.retainedAnimalID,
            replacementAnimalID: fixture.replacementAnimalID,
            retainedName: "Alpha",
            replacementName: "Beta"
        )
        let localActor = SwiftDataHerdSharingActor(modelContainer: local.container)
        let seedExport = try await localActor.makeExport(
            for: local.herd.toSummary(),
            storeDescription: "tombstone-bridge-seed"
        )
        _ = try await fixture.store.writeBridgeSnapshot(
            seedExport.snapshot,
            to: fixture.privateStore
        )

        let targetID = targetsReplacementID
            ? fixture.replacementAnimalID
            : fixture.retainedAnimalID
        let context = fixture.store.persistentContainer.viewContext
        let animalRequest = SharedAnimalRecord.fetchRequest()
        animalRequest.affectedStores = [fixture.privateStore]
        animalRequest.predicate = NSPredicate(format: "publicID == %@", targetID.uuidString)
        let targetRecord = try XCTUnwrap(context.fetch(animalRequest).first)
        context.delete(targetRecord)

        let herdRequest = SharedHerdRecord.fetchRequest()
        herdRequest.affectedStores = [fixture.privateStore]
        herdRequest.predicate = NSPredicate(format: "publicID == %@", fixture.herdID.uuidString)
        let sharedHerd = try XCTUnwrap(context.fetch(herdRequest).first)
        let tombstone = SharedDeletedRecord(context: context)
        context.assign(tombstone, to: fixture.privateStore)
        tombstone.mirrorDeletion(
            publicID: targetID.uuidString,
            herdPublicID: fixture.herdID,
            sourceEntityName: SharedAnimalRecord.entityName,
            deletedAt: fixture.timestamp.addingTimeInterval(10),
            mirroredAt: fixture.timestamp.addingTimeInterval(10)
        )
        tombstone.herd = sharedHerd
        try context.save()

        let contaminated = try await fixture.store.readBridgeSnapshot(
            from: fixture.privateStore,
            requestedHerdPublicID: fixture.herdID,
            storeDescription: "ambiguous-repair-tombstone"
        )
        XCTAssertEqual(contaminated.records(for: .deletions).count, 1)

        do {
            _ = try await fixture.store.importPublicIDRepairBridgeRecordsIntoSwiftData(
                for: local.herd.toSummary(),
                expectedLocation: .ownerPrivateStore,
                expectedFingerprint: contaminated.publicIDRepairFingerprint,
                importer: localActor,
                report: makeRepairReport(fixture: fixture)
            )
            XCTFail("Expected repaired duplicate-group tombstone to remain blocked")
        } catch let error as HerdSharingActionError {
            guard case .bridgeConsistencyFailed(let message) = error else {
                return XCTFail("Unexpected sharing error: \(error)")
            }
            XCTAssertTrue(message.contains("deletion tombstone"))
        }

        let animals = try ModelContext(local.container).fetch(FetchDescriptor<Animal>())
        XCTAssertEqual(animals.count, 2)
        XCTAssertEqual(
            Set(animals.map(\.publicID)),
            [fixture.retainedAnimalID, fixture.replacementAnimalID]
        )
        let unchangedBridge = try await fixture.store.readBridgeSnapshot(
            from: fixture.privateStore,
            requestedHerdPublicID: fixture.herdID,
            storeDescription: "ambiguous-repair-tombstone-after-failure"
        )
        XCTAssertEqual(unchangedBridge.records(for: .deletions).count, 1)
    }

    private func corruptReplacementBridgeAnimalID(
        in fixture: BridgeRepairFixture,
        replacementID: UUID,
        retainedID: UUID
    ) throws {
        let context = fixture.store.persistentContainer.viewContext
        let request = SharedAnimalRecord.fetchRequest()
        request.affectedStores = [fixture.privateStore]
        request.predicate = NSPredicate(format: "publicID == %@", replacementID.uuidString)
        let replacementRecord = try XCTUnwrap(context.fetch(request).first)
        replacementRecord.publicID = retainedID.uuidString
        try context.save()
    }

    private func makeAnimalGraph(
        herdID: UUID,
        retainedAnimalID: UUID,
        replacementAnimalID: UUID,
        retainedName: String,
        replacementName: String,
        useSameAnimalDetails: Bool = false
    ) throws -> AnimalGraph {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herd = Herd(
            publicID: herdID,
            name: "Bridge repair herd",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(herd)

        let retained = Animal(
            publicID: retainedAnimalID,
            name: retainedName,
            tagNumber: "101",
            birthDate: timestamp,
            sex: .female
        )
        retained.herd = herd
        context.insert(retained)

        let replacement = Animal(
            publicID: replacementAnimalID,
            name: replacementName,
            tagNumber: useSameAnimalDetails ? "101" : "202",
            birthDate: useSameAnimalDetails ? timestamp : timestamp.addingTimeInterval(86_400),
            sex: .female
        )
        replacement.herd = herd
        context.insert(replacement)
        try context.save()
        return AnimalGraph(container: container, herd: herd)
    }

    private func makeFixture() throws -> BridgeRepairFixture {
        let herdID = UUID(uuidString: "A1111111-1111-4111-8111-111111111111")!
        let retainedAnimalID = UUID(uuidString: "B2222222-2222-4222-8222-222222222222")!
        let replacementAnimalID = UUID(uuidString: "C3333333-3333-4333-8333-333333333333")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PublicIDRepairDuplicateBridgeTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = HerdSharingCoreDataStore(
            storeDirectoryURL: storeDirectory,
            journalFileURL: storeDirectory.appendingPathComponent("journal.json")
        )
        store.persistentContainer.persistentStoreDescriptions = [
            plainBridgeStoreDescription(
                at: storeDirectory.appendingPathComponent(HerdSharingCoreDataStore.privateStoreFileName)
            ),
            plainBridgeStoreDescription(
                at: storeDirectory.appendingPathComponent(HerdSharingCoreDataStore.sharedStoreFileName)
            ),
        ]
        return BridgeRepairFixture(
            herdID: herdID,
            retainedAnimalID: retainedAnimalID,
            replacementAnimalID: replacementAnimalID,
            timestamp: timestamp,
            storeDirectory: storeDirectory,
            store: store
        )
    }

    private func makeRepairReport(
        fixture: BridgeRepairFixture
    ) -> PublicIDRepairReport {
        PublicIDRepairReport(
            completedAt: fixture.timestamp,
            assessment: PublicIDRepairAssessment(
                scannedAt: fixture.timestamp,
                entities: [
                    PublicIDRepairEntityAssessment(
                        entityType: .animal,
                        scannedRecordCount: 2,
                        duplicateGroupCount: 1,
                        duplicateRecordCount: 1
                    )
                ]
            ),
            replacements: [
                PublicIDRepairReplacement(
                    entityType: .animal,
                    recordDescription: "Beta",
                    stableRecordIdentifier: "animal|duplicate-bridge-regression",
                    retainedPublicID: fixture.retainedAnimalID,
                    replacementPublicID: fixture.replacementAnimalID
                )
            ],
            referenceUpdates: [],
            backupFilename: "duplicate-bridge-regression.json",
            backupPath: "/tmp/duplicate-bridge-regression.json",
            validationIssueCount: 0
        )
    }

    private func plainBridgeStoreDescription(at url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }
}

@MainActor
private final class BridgeRepairFixture {
    let herdID: UUID
    let retainedAnimalID: UUID
    let replacementAnimalID: UUID
    let timestamp: Date
    let storeDirectory: URL
    let store: HerdSharingCoreDataStore
    private(set) var privateStore: NSPersistentStore!

    init(
        herdID: UUID,
        retainedAnimalID: UUID,
        replacementAnimalID: UUID,
        timestamp: Date,
        storeDirectory: URL,
        store: HerdSharingCoreDataStore
    ) {
        self.herdID = herdID
        self.retainedAnimalID = retainedAnimalID
        self.replacementAnimalID = replacementAnimalID
        self.timestamp = timestamp
        self.storeDirectory = storeDirectory
        self.store = store
    }

    func load() async throws {
        try await store.loadIfNeeded()
        privateStore = try XCTUnwrap(store.privateStore)
    }

    func removeStoreDirectory() {
        try? FileManager.default.removeItem(at: storeDirectory)
    }
}

private struct AnimalGraph {
    let container: ModelContainer
    let herd: Herd
}
