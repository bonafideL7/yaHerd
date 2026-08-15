import CoreData
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class PublicIDRepairReplacementHerdBridgeIntegrationTests: XCTestCase {
    func testRepairBridgeImportPreservesChildOwnedByReplacementHerd() async throws {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PublicIDRepairReplacementHerdBridgeTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let coreDataStore = HerdSharingCoreDataStore(
            storeDirectoryURL: storeDirectory,
            journalFileURL: storeDirectory.appendingPathComponent("journal.json")
        )
        coreDataStore.persistentContainer.persistentStoreDescriptions = [
            plainBridgeStoreDescription(
                at: storeDirectory.appendingPathComponent(HerdSharingCoreDataStore.privateStoreFileName)
            ),
            plainBridgeStoreDescription(
                at: storeDirectory.appendingPathComponent(HerdSharingCoreDataStore.sharedStoreFileName)
            ),
        ]
        try await coreDataStore.loadIfNeeded()
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let privateStore = try XCTUnwrap(coreDataStore.privateStore)

        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let retainedHerdID = UUID(uuidString: "61616161-6161-4161-8161-616161616161")!
        let replacementHerdID = UUID(uuidString: "62626262-6262-4262-8262-626262626262")!
        let animalID = UUID(uuidString: "63636363-6363-4363-8363-636363636363")!
        let movementID = UUID(uuidString: "64646464-6464-4464-8464-646464646464")!

        let bridgeSeedContainer = try TestSupport.makeModelContainer()
        let bridgeSeedContext = bridgeSeedContainer.mainContext
        let sharedHerd = Herd(
            publicID: retainedHerdID,
            name: "My Herd",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let sharedAnimal = Animal(
            publicID: animalID,
            name: "Replacement-owned animal",
            tagNumber: "202",
            birthDate: timestamp,
            sex: .female
        )
        sharedAnimal.herd = sharedHerd
        let bridgeOnlyMovement = MovementRecord(
            publicID: movementID,
            date: timestamp,
            fromPasture: nil,
            toPasture: "Replacement pasture",
            animal: sharedAnimal
        )
        bridgeSeedContext.insert(sharedHerd)
        bridgeSeedContext.insert(sharedAnimal)
        bridgeSeedContext.insert(bridgeOnlyMovement)
        try bridgeSeedContext.save()
        let seedActor = SwiftDataHerdSharingActor(modelContainer: bridgeSeedContainer)
        let seedExport = try await seedActor.makeExport(
            for: sharedHerd.toSummary(),
            storeDescription: "replacement-herd bridge seed"
        )
        _ = try await coreDataStore.writeBridgeSnapshot(seedExport.snapshot, to: privateStore)

        let localContainer = try TestSupport.makeModelContainer()
        let localContext = localContainer.mainContext
        let retainedHerd = Herd(
            publicID: retainedHerdID,
            name: "My Herd",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let replacementHerd = Herd(
            publicID: replacementHerdID,
            name: "My Herd",
            createdAt: timestamp.addingTimeInterval(60),
            updatedAt: timestamp.addingTimeInterval(60)
        )
        let localAnimal = Animal(
            publicID: animalID,
            name: "Replacement-owned animal",
            tagNumber: "202",
            birthDate: timestamp,
            sex: .female
        )
        localAnimal.herd = replacementHerd
        localContext.insert(retainedHerd)
        localContext.insert(replacementHerd)
        localContext.insert(localAnimal)
        try localContext.save()

        let bridgeStore = PublicIDRepairOwnershipSafeBridgeStore(base: coreDataStore)
        let baseline = try await bridgeStore.publicIDRepairFingerprint(
            for: retainedHerd.toSummary(),
            expectedLocation: .ownerPrivateStore
        )
        let report = PublicIDRepairReport(
            completedAt: timestamp,
            assessment: PublicIDRepairAssessment(scannedAt: timestamp, entities: []),
            replacements: [
                PublicIDRepairReplacement(
                    entityType: .herd,
                    recordDescription: "My Herd",
                    stableRecordIdentifier: "herd|replacement-owner",
                    retainedPublicID: retainedHerdID,
                    replacementPublicID: replacementHerdID
                )
            ],
            referenceUpdates: [],
            backupFilename: "replacement-herd.json",
            backupPath: "/tmp/replacement-herd.json",
            validationIssueCount: 0
        )

        _ = try await bridgeStore.importPublicIDRepairBridgeRecordsIntoSwiftData(
            for: retainedHerd.toSummary(),
            expectedLocation: .ownerPrivateStore,
            expectedFingerprint: baseline,
            importer: SwiftDataHerdSharingActor(modelContainer: localContainer),
            report: report
        )

        let verificationContext = ModelContext(localContainer)
        let animals = try verificationContext.fetch(FetchDescriptor<Animal>())
        let importedAnimal = try XCTUnwrap(animals.first { $0.publicID == animalID })
        XCTAssertEqual(importedAnimal.herd?.publicID, replacementHerdID)
        XCTAssertEqual(importedAnimal.name, "Replacement-owned animal")
        XCTAssertFalse(
            animals.contains { animal in
                animal.publicID == animalID && animal.herd?.publicID == retainedHerdID
            }
        )

        let movements = try verificationContext.fetch(FetchDescriptor<MovementRecord>())
        let importedMovement = try XCTUnwrap(movements.first { $0.publicID == movementID })
        XCTAssertEqual(importedMovement.herd?.publicID, replacementHerdID)
        XCTAssertEqual(importedMovement.animal?.publicID, animalID)
        XCTAssertEqual(importedMovement.animal?.herd?.publicID, replacementHerdID)
    }

    private func plainBridgeStoreDescription(at url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }
}