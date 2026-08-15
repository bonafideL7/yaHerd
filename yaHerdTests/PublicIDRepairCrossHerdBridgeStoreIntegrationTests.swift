import CoreData
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class PublicIDRepairCrossHerdBridgeStoreIntegrationTests: XCTestCase {
    func testRealBridgeStoreBridgeOnlyCrossHerdCollisionRequiresResolutionBeforeImport() async throws {
        let fixture = try await makeBridgeFixture(
            testDirectory: "PublicIDRepairCrossHerdBridgeStoreTests"
        )
        defer { try? FileManager.default.removeItem(at: fixture.storeDirectory) }

        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herdAID = UUID(uuidString: "51515151-5151-4151-8151-515151515151")!
        let herdBID = UUID(uuidString: "62626262-6262-4262-8262-626262626262")!
        let sharedAnimalID = UUID(uuidString: "73737373-7373-4373-8373-737373737373")!
        try await seedBridgeAnimal(
            store: fixture.store,
            privateStore: fixture.privateStore,
            herdID: herdAID,
            herdName: "Herd A",
            animalID: sharedAnimalID,
            animalName: "Animal A",
            timestamp: timestamp
        )
        try await seedBridgeAnimal(
            store: fixture.store,
            privateStore: fixture.privateStore,
            herdID: herdBID,
            herdName: "Herd B",
            animalID: sharedAnimalID,
            animalName: "Animal B",
            timestamp: timestamp
        )

        let localContainer = try TestSupport.makeModelContainer()
        let localContext = localContainer.mainContext
        let localHerdA = Herd(
            publicID: herdAID,
            name: "Herd A",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let localHerdB = Herd(
            publicID: herdBID,
            name: "Herd B",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        localContext.insert(localHerdA)
        localContext.insert(localHerdB)
        try localContext.save()

        let coordinator = makeCoordinator(
            container: localContainer,
            bridgeStore: fixture.store,
            herds: [localHerdA.toSummary(), localHerdB.toSummary()]
        )
        let preparation = try await coordinator.prepareForRepair()
        var bridgeIssue: PublicIDRepairUnresolvedReference?

        do {
            try await coordinator.convergeAfterRepair(
                preparation: preparation,
                report: repairReport(timestamp: timestamp)
            )
            XCTFail("Expected bridge-only cross-Herd collision to require a deliberate choice")
        } catch let error as PublicIDRepairBridgeResolutionRequired {
            let issue = try XCTUnwrap(error.issues.first)
            bridgeIssue = issue
            XCTAssertEqual(issue.kind, .bridgeRecordOwner)
            XCTAssertEqual(issue.entityType, .animal)
            XCTAssertEqual(issue.referencedPublicID, sharedAnimalID)
            XCTAssertEqual(
                Set(issue.candidates.map(\.resultingPublicID)),
                [herdAID, herdBID]
            )
            XCTAssertEqual(
                Set(issue.bridgeParticipantHerdPublicIDs ?? []),
                [herdAID, herdBID]
            )
            XCTAssertTrue(issue.candidates.contains { $0.recordDescription.contains("Herd A") })
            XCTAssertTrue(issue.candidates.contains { $0.recordDescription.contains("Herd B") })
        }

        let localAnimals = try ModelContext(localContainer).fetch(FetchDescriptor<Animal>())
        XCTAssertTrue(
            localAnimals.isEmpty,
            "No bridge root may be imported before all staged bridge identities pass validation"
        )

        let issue = try XCTUnwrap(bridgeIssue)
        let resolution = PublicIDRepairBridgeCollisionResolution(
            entityType: .animal,
            retainedPublicID: sharedAnimalID,
            selectedHerdPublicID: herdAID,
            herdPublicIDs: issue.bridgeParticipantHerdPublicIDs ?? []
        )
        let lateAnimal = Animal(
            publicID: sharedAnimalID,
            name: "Late Animal B",
            tagNumber: "Late Animal B",
            birthDate: timestamp,
            sex: .female
        )
        lateAnimal.herd = localHerdB
        localContext.insert(lateAnimal)
        try localContext.save()

        let worker = SwiftDataPublicIDRepairService(modelContainer: localContainer)
        let lateReport = try await worker.repair(
            resolutions: resolution.workerResolutionDirectives
        )
        defer { try? FileManager.default.removeItem(atPath: lateReport.backupPath) }
        let expectedReplacement = try XCTUnwrap(
            resolution.replacementPublicID(for: herdBID)
        )
        let repairedLateAnimal = try XCTUnwrap(
            ModelContext(localContainer).fetch(FetchDescriptor<Animal>()).first
        )
        XCTAssertEqual(repairedLateAnimal.publicID, expectedReplacement)
        XCTAssertEqual(lateReport.replacements.first?.replacementPublicID, expectedReplacement)
    }

    func testRealBridgeStoreRepairMappedCrossHerdCollisionConvergesToDistinctIDs() async throws {
        let fixture = try await makeBridgeFixture(
            testDirectory: "PublicIDRepairCrossHerdMappedBridgeStoreTests"
        )
        defer { try? FileManager.default.removeItem(at: fixture.storeDirectory) }

        let timestamp = Date(timeIntervalSince1970: 1_700_000_100)
        let herdAID = UUID(uuidString: "81818181-8181-4181-8181-818181818181")!
        let herdBID = UUID(uuidString: "92929292-9292-4292-8292-929292929292")!
        let retainedAnimalID = UUID(uuidString: "A3A3A3A3-A3A3-43A3-83A3-A3A3A3A3A3A3")!
        try await seedBridgeAnimal(
            store: fixture.store,
            privateStore: fixture.privateStore,
            herdID: herdAID,
            herdName: "Mapped Herd A",
            animalID: retainedAnimalID,
            animalName: "Animal A",
            timestamp: timestamp
        )
        try await seedBridgeAnimal(
            store: fixture.store,
            privateStore: fixture.privateStore,
            herdID: herdBID,
            herdName: "Mapped Herd B",
            animalID: retainedAnimalID,
            animalName: "Animal B",
            timestamp: timestamp
        )

        let localContainer = try TestSupport.makeModelContainer()
        let localContext = localContainer.mainContext
        let localHerdA = Herd(
            publicID: herdAID,
            name: "Mapped Herd A",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let localHerdB = Herd(
            publicID: herdBID,
            name: "Mapped Herd B",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let localAnimalA = Animal(
            publicID: retainedAnimalID,
            name: "Animal A",
            tagNumber: "Animal A",
            birthDate: timestamp,
            sex: .female
        )
        localAnimalA.herd = localHerdA
        let localAnimalB = Animal(
            publicID: retainedAnimalID,
            name: "Animal B",
            tagNumber: "Animal B",
            birthDate: timestamp,
            sex: .female
        )
        localAnimalB.herd = localHerdB
        localContext.insert(localHerdA)
        localContext.insert(localHerdB)
        localContext.insert(localAnimalA)
        localContext.insert(localAnimalB)
        try localContext.save()

        let coordinator = makeCoordinator(
            container: localContainer,
            bridgeStore: fixture.store,
            herds: [localHerdA.toSummary(), localHerdB.toSummary()]
        )
        let preparation = try await coordinator.prepareForRepair()
        let worker = SwiftDataPublicIDRepairService(modelContainer: localContainer)
        let report = try await worker.repair()
        defer { try? FileManager.default.removeItem(atPath: report.backupPath) }

        let resolution = try XCTUnwrap(report.bridgeCollisionResolutions?.first)
        XCTAssertEqual(resolution.entityType, .animal)
        XCTAssertEqual(resolution.retainedPublicID, retainedAnimalID)
        XCTAssertEqual(Set(resolution.herdPublicIDs), [herdAID, herdBID])
        let nonOwnerHerdID = try XCTUnwrap(
            resolution.herdPublicIDs.first { $0 != resolution.selectedHerdPublicID }
        )
        let replacementAnimalID = try XCTUnwrap(
            resolution.replacementPublicID(for: nonOwnerHerdID)
        )
        XCTAssertEqual(report.replacements.count, 1)
        XCTAssertEqual(report.replacements.first?.replacementPublicID, replacementAnimalID)
        XCTAssertTrue(report.userReadableSummary.contains("Shared identity decisions:"))
        XCTAssertTrue(report.userReadableSummary.contains(resolution.selectedHerdPublicID.uuidString))
        XCTAssertTrue(report.userReadableSummary.contains(replacementAnimalID.uuidString))

        try await coordinator.convergeAfterRepair(
            preparation: preparation,
            report: report
        )

        let verificationContext = ModelContext(localContainer)
        let animals = try verificationContext.fetch(FetchDescriptor<Animal>())
        XCTAssertEqual(Set(animals.map(\.publicID)), [retainedAnimalID, replacementAnimalID])
        XCTAssertEqual(
            animals.first { $0.herd?.publicID == resolution.selectedHerdPublicID }?.publicID,
            retainedAnimalID
        )
        XCTAssertEqual(
            animals.first { $0.herd?.publicID == nonOwnerHerdID }?.publicID,
            replacementAnimalID
        )

        let bridgeA = try await fixture.store.readBridgeSnapshot(
            from: fixture.privateStore,
            requestedHerdPublicID: herdAID,
            storeDescription: "mapped-bridge-a"
        )
        let bridgeB = try await fixture.store.readBridgeSnapshot(
            from: fixture.privateStore,
            requestedHerdPublicID: herdBID,
            storeDescription: "mapped-bridge-b"
        )
        let expectedBridgeAID = resolution.selectedHerdPublicID == herdAID
            ? retainedAnimalID
            : replacementAnimalID
        let expectedBridgeBID = resolution.selectedHerdPublicID == herdBID
            ? retainedAnimalID
            : replacementAnimalID
        XCTAssertEqual(
            Set(bridgeA.records(for: .animals).compactMap(\.parsedPublicID)),
            [expectedBridgeAID]
        )
        XCTAssertEqual(
            Set(bridgeB.records(for: .animals).compactMap(\.parsedPublicID)),
            [expectedBridgeBID]
        )
    }

    func testProductionOwnershipSafeWrapperForwardsPreparedBridgeRetirement() async throws {
        let fixture = try await makeBridgeFixture(
            testDirectory: "PublicIDRepairProductionWrapperRetirementTests"
        )
        defer { try? FileManager.default.removeItem(at: fixture.storeDirectory) }

        let timestamp = Date(timeIntervalSince1970: 1_700_000_200)
        let targetHerdID = UUID(uuidString: "B4B4B4B4-B4B4-44B4-84B4-B4B4B4B4B4B4")!
        let unrelatedHerdID = UUID(uuidString: "C5C5C5C5-C5C5-45C5-85C5-C5C5C5C5C5C5")!
        let targetAnimalID = UUID(uuidString: "D6D6D6D6-D6D6-46D6-86D6-D6D6D6D6D6D6")!
        let unrelatedAnimalID = UUID(uuidString: "E7E7E7E7-E7E7-47E7-87E7-E7E7E7E7E7E7")!
        try await seedBridgeAnimal(
            store: fixture.store,
            privateStore: fixture.privateStore,
            herdID: targetHerdID,
            herdName: "Retirement target",
            animalID: targetAnimalID,
            animalName: "Target animal",
            timestamp: timestamp
        )
        try await seedBridgeAnimal(
            store: fixture.store,
            privateStore: fixture.privateStore,
            herdID: unrelatedHerdID,
            herdName: "Unrelated herd",
            animalID: unrelatedAnimalID,
            animalName: "Unrelated animal",
            timestamp: timestamp
        )

        let targetHerd = HerdSummary(
            publicID: targetHerdID,
            name: "Retirement target",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let targetBefore = try await fixture.store.readBridgeSnapshot(
            from: fixture.privateStore,
            requestedHerdPublicID: targetHerdID,
            storeDescription: "retirement-target-before"
        )
        XCTAssertEqual(
            Set(targetBefore.records(for: .herd).compactMap(\.parsedPublicID)),
            [targetHerdID]
        )
        XCTAssertEqual(
            Set(targetBefore.records(for: .animals).compactMap(\.parsedPublicID)),
            [targetAnimalID]
        )

        let wrapper = PublicIDRepairOwnershipSafeBridgeStore(base: fixture.store)
        let erasedStore: any PublicIDRepairBridgeStore = wrapper
        XCTAssertNotNil(
            erasedStore as? any PublicIDRepairBridgeRetiringStore,
            "The production ownership-safe wrapper must expose the existing retirement capability"
        )
        let exporter = SwiftDataPublicIDRepairBridgeExporter(
            modelContainer: try TestSupport.makeModelContainer(),
            bridgeStore: erasedStore
        )
        let access = HerdSharingAccess.ownerPrivateStore(participantCount: 1)
        let preflight = try await wrapper.publicIDRepairPreflight(
            for: targetHerd,
            expectedLocation: .ownerPrivateStore
        )
        let preparedTarget = PublicIDRepairBridgeTargetIdentity(
            herdPublicID: targetHerdID,
            location: .ownerPrivateStore,
            bridgeFingerprint: preflight.fingerprint
        )
        let changedFingerprintTarget = PublicIDRepairBridgeTargetIdentity(
            herdPublicID: targetHerdID,
            location: .ownerPrivateStore,
            bridgeFingerprint: preflight.fingerprint + "-changed"
        )

        do {
            try await exporter.retirePreparedBridge(
                for: targetHerd,
                access: access,
                target: changedFingerprintTarget
            )
            XCTFail("Expected changed fingerprint to fail closed")
        } catch let error as HerdSharingPublicIDRepairBridgeError {
            guard case .bridgeContentChanged = error else {
                XCTFail("Expected fingerprint verification failure, got \(error)")
                return
            }
        } catch let error as PublicIDRepairBridgeError {
            if case .bridgeRetirementUnavailable = error {
                XCTFail("Production wrapper did not forward retirement capability")
            } else {
                XCTFail("Unexpected exporter-level retirement error: \(error)")
            }
            return
        }

        let targetAfterRejectedFingerprint = try await fixture.store.readBridgeSnapshot(
            from: fixture.privateStore,
            requestedHerdPublicID: targetHerdID,
            storeDescription: "retirement-target-after-rejected-fingerprint"
        )
        XCTAssertEqual(
            Set(targetAfterRejectedFingerprint.records(for: .animals).compactMap(\.parsedPublicID)),
            [targetAnimalID]
        )

        try await exporter.retirePreparedBridge(
            for: targetHerd,
            access: access,
            target: preparedTarget
        )

        do {
            _ = try await fixture.store.readBridgeSnapshot(
                from: fixture.privateStore,
                requestedHerdPublicID: targetHerdID,
                storeDescription: "retirement-target-after"
            )
            XCTFail("Expected the retired Herd root to be absent")
        } catch let error as HerdSharingBridgeSnapshotError {
            guard case .missingHerdRecord(let missingHerdID) = error else {
                XCTFail("Expected retired Herd graph to be absent, got \(error)")
                return
            }
            XCTAssertEqual(missingHerdID, targetHerdID)
        }

        let unrelatedAfter = try await fixture.store.readBridgeSnapshot(
            from: fixture.privateStore,
            requestedHerdPublicID: unrelatedHerdID,
            storeDescription: "retirement-unrelated-after"
        )
        XCTAssertEqual(
            Set(unrelatedAfter.records(for: .herd).compactMap(\.parsedPublicID)),
            [unrelatedHerdID]
        )
        XCTAssertEqual(
            Set(unrelatedAfter.records(for: .animals).compactMap(\.parsedPublicID)),
            [unrelatedAnimalID]
        )
    }

    private func makeCoordinator(
        container: ModelContainer,
        bridgeStore: HerdSharingCoreDataStore,
        herds: [HerdSummary]
    ) -> DefaultPublicIDRepairBridgeCoordinator {
        DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: CrossHerdStoreInventory(herds: herds),
            sharingRepository: CrossHerdStoreSharingRepository(),
            storageMode: .iCloud,
            exporter: SwiftDataPublicIDRepairBridgeExporter(
                modelContainer: container,
                bridgeStore: PublicIDRepairOwnershipSafeBridgeStore(base: bridgeStore)
            )
        )
    }

    private func makeBridgeFixture(
        testDirectory: String
    ) async throws -> CrossHerdBridgeFixture {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(testDirectory, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bridgeStore = HerdSharingCoreDataStore(
            storeDirectoryURL: storeDirectory,
            journalFileURL: storeDirectory.appendingPathComponent("journal.json")
        )
        bridgeStore.persistentContainer.persistentStoreDescriptions = [
            plainBridgeStoreDescription(
                at: storeDirectory.appendingPathComponent(HerdSharingCoreDataStore.privateStoreFileName)
            ),
            plainBridgeStoreDescription(
                at: storeDirectory.appendingPathComponent(HerdSharingCoreDataStore.sharedStoreFileName)
            ),
        ]
        try await bridgeStore.loadIfNeeded()
        return CrossHerdBridgeFixture(
            storeDirectory: storeDirectory,
            store: bridgeStore,
            privateStore: try XCTUnwrap(bridgeStore.privateStore)
        )
    }

    private func seedBridgeAnimal(
        store: HerdSharingCoreDataStore,
        privateStore: NSPersistentStore,
        herdID: UUID,
        herdName: String,
        animalID: UUID,
        animalName: String,
        timestamp: Date
    ) async throws {
        let graph = try makeBridgeGraph(
            herdID: herdID,
            herdName: herdName,
            animalID: animalID,
            animalName: animalName,
            timestamp: timestamp
        )
        let actor = SwiftDataHerdSharingActor(modelContainer: graph.container)
        let export = try await actor.makeExport(
            for: graph.herd.toSummary(),
            storeDescription: "cross-herd-seed"
        )
        _ = try await store.writeBridgeSnapshot(export.snapshot, to: privateStore)
    }

    private func repairReport(timestamp: Date) -> PublicIDRepairReport {
        PublicIDRepairReport(
            completedAt: timestamp,
            assessment: PublicIDRepairAssessment(scannedAt: timestamp, entities: []),
            replacements: [],
            referenceUpdates: [],
            backupFilename: "cross-herd-store.json",
            backupPath: "/tmp/cross-herd-store.json",
            validationIssueCount: 0
        )
    }

    private func makeBridgeGraph(
        herdID: UUID,
        herdName: String,
        animalID: UUID,
        animalName: String,
        timestamp: Date
    ) throws -> CrossHerdStoreGraph {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let herd = Herd(
            publicID: herdID,
            name: herdName,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let animal = Animal(
            publicID: animalID,
            name: animalName,
            tagNumber: animalName,
            birthDate: timestamp,
            sex: .female
        )
        animal.herd = herd
        context.insert(herd)
        context.insert(animal)
        try context.save()
        return CrossHerdStoreGraph(container: container, herd: herd)
    }

    private func plainBridgeStoreDescription(at url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }
}

private struct CrossHerdBridgeFixture {
    let storeDirectory: URL
    let store: HerdSharingCoreDataStore
    let privateStore: NSPersistentStore
}

private struct CrossHerdStoreGraph {
    let container: ModelContainer
    let herd: Herd
}

private actor CrossHerdStoreInventory: PublicIDRepairHerdInventoryReading {
    let herds: [HerdSummary]

    init(herds: [HerdSummary]) {
        self.herds = herds
    }

    func fetchHerds() async throws -> [HerdSummary] {
        herds
    }
}

@MainActor
private final class CrossHerdStoreSharingRepository: HerdSharingRepository {
    func fetchSharingReadiness(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) -> HerdSharingReadiness {
        .sharingAdapterAvailable
    }

    func fetchSharingAccess(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingAccess {
        .ownerPrivateStore(participantCount: 1)
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        result("start")
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        result("accept")
    }

    func importSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        result("import")
    }

    func acceptPreventedSharedDeletes(
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        result("delete")
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        result("restore")
    }

    func syncSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        result("sync")
    }

    private func result(_ value: String) -> HerdSharingActionResult {
        HerdSharingActionResult(title: value, message: value)
    }
}
