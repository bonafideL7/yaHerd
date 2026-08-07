import CoreData
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class PublicIDRepairReviewRound2RegressionTests: XCTestCase {
    func testExistingBridgeUsesRealImporterOnlyAfterLocalDuplicateIDsAreRepaired() async throws {
        let herdID = UUID(uuidString: "11111111-AAAA-4111-8111-111111111111")!
        let duplicateAnimalID = UUID(uuidString: "22222222-BBBB-4222-8222-222222222222")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let localContainer = try TestSupport.makeModelContainer()
        let localContext = localContainer.mainContext
        let localHerd = Herd(
            publicID: herdID,
            name: "Local herd",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        localContext.insert(localHerd)
        let first = Animal(
            publicID: duplicateAnimalID,
            name: "Local first",
            tagNumber: "101",
            birthDate: timestamp,
            sex: .female
        )
        first.herd = localHerd
        localContext.insert(first)
        let second = Animal(
            publicID: duplicateAnimalID,
            name: "Local second",
            tagNumber: "102",
            birthDate: timestamp.addingTimeInterval(1),
            sex: .female
        )
        second.herd = localHerd
        localContext.insert(second)
        try localContext.save()

        let bridgeContainer = try TestSupport.makeModelContainer()
        let bridgeContext = bridgeContainer.mainContext
        let bridgeHerd = Herd(
            publicID: herdID,
            name: "Shared herd",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        bridgeContext.insert(bridgeHerd)
        let sharedAnimal = Animal(
            publicID: duplicateAnimalID,
            name: "Shared animal",
            tagNumber: "101",
            birthDate: timestamp,
            sex: .female
        )
        sharedAnimal.herd = bridgeHerd
        bridgeContext.insert(sharedAnimal)
        try bridgeContext.save()

        let bridgeReader = SwiftDataHerdSharingActor(modelContainer: bridgeContainer)
        let bridgeExport = try await bridgeReader.makeExport(
            for: bridgeHerd.toSummary(),
            storeDescription: "round-two-existing-bridge"
        )
        let bridgeStore = RealImporterRepairBridgeStore(snapshot: bridgeExport.snapshot)
        let repository = RoundTwoSharingRepository(
            sharedHerdID: herdID,
            sharedAccess: .ownerPrivateStore(participantCount: 1)
        )
        let exporter = SwiftDataPublicIDRepairBridgeExporter(
            modelContainer: localContainer,
            bridgeStore: bridgeStore
        )
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: SwiftDataPublicIDRepairHerdInventory(modelContainer: localContainer),
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )
        let journalURL = temporaryJournalURL()
        defer { try? FileManager.default.removeItem(at: journalURL.deletingLastPathComponent()) }
        let gate = HerdDataMutationGate(
            defaults: isolatedDefaults(),
            journalFileURL: journalURL
        )
        let service = CoordinatedPublicIDRepairService(
            worker: SwiftDataPublicIDRepairService(modelContainer: localContainer),
            mutationGate: gate,
            bridgeCoordinator: coordinator
        )

        let report = try await service.repair()
        defer { try? FileManager.default.removeItem(atPath: report.backupPath) }

        let verificationContext = ModelContext(localContainer)
        let animals = try verificationContext.fetch(FetchDescriptor<Animal>())
        XCTAssertEqual(animals.count, 2)
        XCTAssertEqual(Set(animals.map(\.publicID)).count, 2)
        XCTAssertEqual(report.replacements.filter { $0.entityType == .animal }.count, 1)
        XCTAssertEqual(bridgeStore.importCallCount, 1)
        XCTAssertEqual(bridgeStore.syncCallCount, 1)
        XCTAssertEqual(repository.normalImportCallCount, 0)
        XCTAssertFalse(gate.requiresBridgeConvergence)
    }

    func testDuplicateHerdOwnerCanChooseWhichRecordKeepsExistingShareIdentity() async throws {
        try await verifyDuplicateHerdRecovery(
            sharedAccess: .ownerPrivateStore(participantCount: 2)
        )
    }

    func testDuplicateHerdReadWriteParticipantCanChooseWhichRecordKeepsExistingShareIdentity() async throws {
        try await verifyDuplicateHerdRecovery(
            sharedAccess: .acceptedSharedStore(
                permission: .readWrite,
                participantCount: 2
            )
        )
    }

    func testReplacementIDTombstoneIsFingerprintVisibleRemovedByConvergenceAndCannotDeleteLiveImport() async throws {
        let herdID = UUID(uuidString: "33333333-CCCC-4333-8333-333333333333")!
        let replacementAnimalID = UUID(uuidString: "44444444-DDDD-4444-8444-444444444444")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let exportContainer = try TestSupport.makeModelContainer()
        let exportContext = exportContainer.mainContext
        let herd = Herd(
            publicID: herdID,
            name: "Tombstone herd",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        exportContext.insert(herd)
        let repairedAnimal = Animal(
            publicID: replacementAnimalID,
            name: "Repaired live animal",
            tagNumber: "404",
            birthDate: timestamp,
            sex: .female
        )
        repairedAnimal.herd = herd
        exportContext.insert(repairedAnimal)
        try exportContext.save()

        let reader = SwiftDataHerdSharingActor(modelContainer: exportContainer)
        let export = try await reader.makeExport(
            for: herd.toSummary(),
            storeDescription: "round-two-tombstone-desired"
        )

        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PublicIDRepairRound2CoreData", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
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
        try await store.loadIfNeeded()
        let privateStore = try XCTUnwrap(store.privateStore)

        _ = try await store.writeBridgeSnapshot(export.snapshot, to: privateStore)

        let coreDataContext = store.persistentContainer.viewContext
        let herdRequest = SharedHerdRecord.fetchRequest()
        herdRequest.affectedStores = [privateStore]
        herdRequest.predicate = NSPredicate(format: "publicID == %@", herdID.uuidString)
        let sharedHerd = try XCTUnwrap(coreDataContext.fetch(herdRequest).first)
        let tombstone = SharedDeletedRecord(context: coreDataContext)
        coreDataContext.assign(tombstone, to: privateStore)
        tombstone.mirrorDeletion(
            publicID: replacementAnimalID.uuidString,
            herdPublicID: herdID,
            sourceEntityName: SharedAnimalRecord.entityName,
            deletedAt: timestamp.addingTimeInterval(10),
            mirroredAt: timestamp.addingTimeInterval(10)
        )
        tombstone.herd = sharedHerd
        try coreDataContext.save()

        let contaminated = try await store.readBridgeSnapshot(
            from: privateStore,
            requestedHerdPublicID: herdID,
            storeDescription: "round-two-contaminated"
        )
        XCTAssertEqual(contaminated.records(for: .deletions).count, 1)
        XCTAssertNotEqual(
            contaminated.publicIDRepairFingerprint,
            export.snapshot.publicIDRepairFingerprint,
            "A semantic deletion tombstone must participate in repair fingerprint validation"
        )

        _ = try await store.writeBridgeSnapshot(export.snapshot, to: privateStore)
        let converged = try await store.readBridgeSnapshot(
            from: privateStore,
            requestedHerdPublicID: herdID,
            storeDescription: "round-two-converged"
        )
        XCTAssertTrue(converged.records(for: .deletions).isEmpty)
        XCTAssertEqual(
            converged.publicIDRepairFingerprint,
            export.snapshot.publicIDRepairFingerprint
        )

        let importContainer = try TestSupport.makeModelContainer()
        let importContext = importContainer.mainContext
        importContext.insert(
            Herd(
                publicID: herdID,
                name: "Import target",
                createdAt: timestamp,
                updatedAt: timestamp
            )
        )
        try importContext.save()
        let importer = SwiftDataHerdSharingActor(modelContainer: importContainer)
        _ = try await importer.applyImport(
            converged,
            pendingConflictReport: nil,
            failureInjector: .disabled
        )

        let importedAnimals = try ModelContext(importContainer).fetch(FetchDescriptor<Animal>())
        XCTAssertEqual(importedAnimals.map(\.publicID), [replacementAnimalID])
    }

    private func verifyDuplicateHerdRecovery(
        sharedAccess: HerdSharingAccess
    ) async throws {
        let duplicatedHerdID = UUID(uuidString: "55555555-EEEE-4555-8555-555555555555")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let sharedHerd = Herd(
            publicID: duplicatedHerdID,
            name: "Shared herd",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let separateHerd = Herd(
            publicID: duplicatedHerdID,
            name: "Separate herd",
            createdAt: timestamp.addingTimeInterval(1),
            updatedAt: timestamp.addingTimeInterval(1)
        )
        context.insert(sharedHerd)
        context.insert(separateHerd)
        try context.save()

        let repository = RoundTwoSharingRepository(
            sharedHerdID: duplicatedHerdID,
            sharedAccess: sharedAccess
        )
        let exporter = RoundTwoBridgeExporter()
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: SwiftDataPublicIDRepairHerdInventory(modelContainer: container),
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )
        let journalURL = temporaryJournalURL()
        defer { try? FileManager.default.removeItem(at: journalURL.deletingLastPathComponent()) }
        let gate = HerdDataMutationGate(
            defaults: isolatedDefaults(),
            journalFileURL: journalURL
        )
        let service = CoordinatedPublicIDRepairService(
            worker: SwiftDataPublicIDRepairService(modelContainer: container),
            mutationGate: gate,
            bridgeCoordinator: coordinator
        )

        let assessment = try await service.scan()
        let issue = try XCTUnwrap(
            assessment.unresolvedReferences.first {
                $0.entityType == .herd && $0.fieldName == "sharedBridgeOwner"
            }
        )
        XCTAssertEqual(issue.candidates.count, 2)
        let selected = try XCTUnwrap(
            issue.candidates.first { $0.recordDescription == "Shared herd" }
        )
        let resolution = PublicIDRepairReferenceResolution(
            unresolvedReferenceID: issue.id,
            selectedCandidateStableRecordIdentifier: selected.stableRecordIdentifier
        )

        let report = try await service.repair(resolutions: [resolution])
        defer { try? FileManager.default.removeItem(atPath: report.backupPath) }

        let verificationContext = ModelContext(container)
        let herds = try verificationContext.fetch(FetchDescriptor<Herd>())
        XCTAssertEqual(herds.count, 2)
        XCTAssertEqual(Set(herds.map(\.publicID)).count, 2)
        XCTAssertEqual(
            herds.first { $0.name == "Shared herd" }?.publicID,
            duplicatedHerdID
        )
        let replacement = try XCTUnwrap(
            report.replacements.first { $0.entityType == .herd }
        )
        XCTAssertEqual(
            herds.first { $0.name == "Separate herd" }?.publicID,
            replacement.replacementPublicID
        )

        let originalTarget = try XCTUnwrap(
            exporter.exportedTargets.first { $0.herdPublicID == duplicatedHerdID }
        )
        let replacementTarget = try XCTUnwrap(
            exporter.exportedTargets.first {
                $0.herdPublicID == replacement.replacementPublicID
            }
        )
        XCTAssertEqual(originalTarget.location, bridgeLocationIdentity(sharedAccess.bridgeLocation))
        XCTAssertEqual(replacementTarget.location, .bridgeRecordMissing)
        XCTAssertEqual(exporter.importedHerdIDs, [duplicatedHerdID])
        XCTAssertEqual(repository.normalImportCallCount, 0)
        XCTAssertFalse(gate.requiresBridgeConvergence)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PublicIDRepairReviewRound2RegressionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func temporaryJournalURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PublicIDRepairReviewRound2RegressionTests-\(UUID().uuidString)",
                isDirectory: true
            )
            .appendingPathComponent("PendingState.json")
    }

    private func plainBridgeStoreDescription(at url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }

    private func bridgeLocationIdentity(
        _ location: HerdSharingAccess.BridgeLocation
    ) -> PublicIDRepairBridgeLocationIdentity {
        switch location {
        case .bridgeRecordMissing: .bridgeRecordMissing
        case .ownerPrivateStore: .ownerPrivateStore
        case .acceptedSharedStore: .acceptedSharedStore
        }
    }
}

@MainActor
private final class RealImporterRepairBridgeStore: PublicIDRepairBridgeStore {
    let snapshot: HerdSharingBridgeStoreSnapshot
    private(set) var importCallCount = 0
    private(set) var syncCallCount = 0

    init(snapshot: HerdSharingBridgeStoreSnapshot) {
        self.snapshot = snapshot
    }

    func publicIDRepairFingerprint(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation
    ) async throws -> String {
        snapshot.publicIDRepairFingerprint
    }

    func importPublicIDRepairBridgeRecordsIntoSwiftData(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation,
        expectedFingerprint: String,
        importer: any HerdSharingImportApplying,
        report: PublicIDRepairReport
    ) async throws -> HerdSharingBridgeImportResult {
        guard expectedFingerprint == snapshot.publicIDRepairFingerprint else {
            throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
                herdPublicID: herd.publicID
            )
        }
        importCallCount += 1
        if let revisionHydrator = importer as? any CollaborationRevisionHydrating {
            try await revisionHydrator.hydrateCollaborationRevisions(for: snapshot.herdPublicID)
        }
        let application = try await importer.applyImport(
            snapshot,
            pendingConflictReport: nil,
            failureInjector: .disabled
        )
        return application.result
    }

    func syncPublicIDRepairBridgeRecordsFromSnapshot(
        _ export: HerdSharingSwiftDataExport,
        expectedLocation: HerdSharingAccess.BridgeLocation,
        expectedFingerprint: String
    ) async throws -> HerdSharingBridgeExportResult {
        guard expectedFingerprint == snapshot.publicIDRepairFingerprint else {
            throw HerdSharingPublicIDRepairBridgeError.bridgeContentChanged(
                herdPublicID: export.herd.publicID
            )
        }
        syncCallCount += 1
        return roundTwoExportResult(for: export.herd)
    }
}

@MainActor
private final class RoundTwoBridgeExporter: PublicIDRepairBridgeExporting {
    private(set) var importedHerdIDs: [UUID] = []
    private(set) var exportedTargets: [PublicIDRepairBridgeTargetIdentity] = []

    func captureBridgeFingerprint(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> String {
        "round-two|\(herd.publicID.uuidString)|\(bridgeLocation(access.bridgeLocation).rawValue)"
    }

    func importCurrentBridgeGraph(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        expectedFingerprint: String,
        report: PublicIDRepairReport
    ) async throws {
        importedHerdIDs.append(herd.publicID)
    }

    func exportRepairedGraph(
        for herd: HerdSummary,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws -> HerdSharingBridgeReconciliationReport {
        XCTAssertNotNil(target.bridgeFingerprint)
        exportedTargets.append(target)
        return .empty
    }

    private func bridgeLocation(
        _ location: HerdSharingAccess.BridgeLocation
    ) -> PublicIDRepairBridgeLocationIdentity {
        switch location {
        case .bridgeRecordMissing: .bridgeRecordMissing
        case .ownerPrivateStore: .ownerPrivateStore
        case .acceptedSharedStore: .acceptedSharedStore
        }
    }
}

@MainActor
private final class RoundTwoSharingRepository: HerdSharingRepository {
    let sharedHerdID: UUID
    let sharedAccess: HerdSharingAccess
    private(set) var normalImportCallCount = 0

    init(
        sharedHerdID: UUID,
        sharedAccess: HerdSharingAccess
    ) {
        self.sharedHerdID = sharedHerdID
        self.sharedAccess = sharedAccess
    }

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
        guard herd?.publicID == sharedHerdID else {
            return .localOwnerBridgePending
        }
        return sharedAccess
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        actionResult("start")
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        actionResult("accept")
    }

    func importSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        normalImportCallCount += 1
        return actionResult("normal-import")
    }

    func acceptPreventedSharedDeletes(
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        actionResult("delete")
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        actionResult("restore")
    }

    func syncSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        actionResult("sync")
    }

    private func actionResult(_ value: String) -> HerdSharingActionResult {
        HerdSharingActionResult(title: value, message: value)
    }
}

private func roundTwoExportResult(
    for herd: HerdSummary
) -> HerdSharingBridgeExportResult {
    HerdSharingBridgeExportResult(
        herdName: herd.name,
        writeTargetDescription: "round-two",
        didUpdateExistingCloudKitShare: false,
        exportedTagColorDefinitionCount: 0,
        exportedStatusReferenceCount: 0,
        exportedAnimalTagCount: 0,
        exportedPastureGroupCount: 0,
        exportedPastureCount: 0,
        exportedAnimalCount: 0,
        exportedMovementCount: 0,
        exportedStatusRecordCount: 0,
        exportedHealthRecordCount: 0,
        exportedPregnancyCheckCount: 0,
        exportedWorkingProtocolTemplateCount: 0,
        exportedWorkingSessionCount: 0,
        exportedWorkingQueueItemCount: 0,
        exportedWorkingTreatmentRecordCount: 0,
        exportedFieldCheckSessionCount: 0,
        exportedFieldCheckAnimalCheckCount: 0,
        exportedFieldCheckFindingCount: 0,
        exportedDeletedRecordCount: 0,
        reconciliationReport: .empty
    )
}
