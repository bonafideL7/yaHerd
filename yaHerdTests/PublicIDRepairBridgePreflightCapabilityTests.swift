import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class PublicIDRepairBridgePreflightCapabilityTests: XCTestCase {
    func testExporterUsesPreflightCapabilityThroughWrappedBridgeStoreAbstraction() async throws {
        let container = try TestSupport.makeModelContainer()
        let herdID = UUID(uuidString: "51515151-5151-4151-8151-515151515151")!
        let childID = UUID(uuidString: "52525252-5252-4252-8252-525252525252")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herd = HerdSummary(
            publicID: herdID,
            name: "Preflight",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let expected = PublicIDRepairBridgePreflight(
            fingerprint: "wrapped-preflight",
            recordIdentities: [
                PublicIDRepairBridgeRecordIdentity(step: .animals, publicID: childID)
            ]
        )
        let bridgeStore = PreflightCapableBridgeStore(preflight: expected)
        let exporter = SwiftDataPublicIDRepairBridgeExporter(
            modelContainer: container,
            bridgeStore: bridgeStore
        )

        let actual = try await exporter.captureBridgePreflight(
            for: herd,
            access: .ownerPrivateStore(participantCount: 1)
        )

        XCTAssertEqual(actual.fingerprint, expected.fingerprint)
        XCTAssertEqual(actual.recordIdentities, expected.recordIdentities)
        XCTAssertEqual(bridgeStore.preflightCallCount, 1)
        XCTAssertEqual(bridgeStore.fingerprintCallCount, 0)
    }

    func testUnrelatedReadOnlyObservedBridgeDoesNotBlockOrBecomeExportTarget() async throws {
        let writable = makeScopeHerd(
            id: "61616161-6161-4161-8161-616161616161",
            name: "Writable"
        )
        let readOnly = makeScopeHerd(
            id: "62626262-6262-4262-8262-626262626262",
            name: "Observed read only"
        )
        let inventory = ScopeInventory(herds: [writable, readOnly])
        let repository = ScopeSharingRepository(
            accessByHerdID: [
                writable.publicID: .ownerPrivateStore(participantCount: 1),
                readOnly.publicID: .acceptedSharedStore(
                    permission: .readOnly,
                    participantCount: 2
                ),
            ]
        )
        let exporter = ScopeExporter(
            preflightByHerdID: [
                writable.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "writable-baseline",
                    recordIdentities: [
                        PublicIDRepairBridgeRecordIdentity(
                            step: .animals,
                            publicID: scopeOriginalID
                        )
                    ]
                ),
                readOnly.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "readonly-baseline",
                    recordIdentities: [
                        PublicIDRepairBridgeRecordIdentity(
                            step: .animals,
                            publicID: UUID(uuidString: "64646464-6464-4464-8464-646464646464")!
                        )
                    ]
                ),
            ]
        )
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )
        let report = affectedScopeReport(herdID: writable.publicID)

        let preparation = try await coordinator.prepareForRepair()
        XCTAssertEqual(Set(preparation.herdPublicIDs), Set([writable.publicID, readOnly.publicID]))

        _ = try await coordinator.validateMutationAuthority(
            preparation: preparation,
            report: report
        )
        try await coordinator.convergeAfterRepair(
            preparation: preparation,
            report: report
        )

        XCTAssertEqual(exporter.importedHerdIDs, [writable.publicID])
        XCTAssertEqual(exporter.exportedHerdIDs, [writable.publicID])
        XCTAssertFalse(exporter.exportedHerdIDs.contains(readOnly.publicID))
        XCTAssertGreaterThanOrEqual(exporter.preflightCallCountByHerdID[readOnly.publicID] ?? 0, 2)
    }

    func testReadOnlyCollisionParticipantBlocksBeforeLocalMutationAuthorityIsGranted() async throws {
        let writable = makeScopeHerd(
            id: "71717171-7171-4171-8171-717171717171",
            name: "Writable"
        )
        let readOnly = makeScopeHerd(
            id: "72727272-7272-4272-8272-727272727272",
            name: "Read-only collision participant"
        )
        let collisionID = UUID(uuidString: "73737373-7373-4373-8373-737373737373")!
        let collisionIdentity = PublicIDRepairBridgeRecordIdentity(
            step: .animals,
            publicID: collisionID
        )
        let inventory = ScopeInventory(herds: [writable, readOnly])
        let repository = ScopeSharingRepository(
            accessByHerdID: [
                writable.publicID: .ownerPrivateStore(participantCount: 1),
                readOnly.publicID: .acceptedSharedStore(
                    permission: .readOnly,
                    participantCount: 2
                ),
            ]
        )
        let exporter = ScopeExporter(
            preflightByHerdID: [
                writable.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "writable-collision",
                    recordIdentities: [
                        collisionIdentity,
                        PublicIDRepairBridgeRecordIdentity(
                            step: .animals,
                            publicID: scopeOriginalID
                        ),
                    ]
                ),
                readOnly.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "readonly-collision",
                    recordIdentities: [collisionIdentity]
                ),
            ]
        )
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )
        let preparation = try await coordinator.prepareForRepair()

        do {
            _ = try await coordinator.validateMutationAuthority(
                preparation: preparation,
                report: affectedScopeReport(herdID: writable.publicID)
            )
            XCTFail("Expected affected read-only collision participant to block pre-commit authority")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(
                error,
                .writePermissionRequired(
                    herdPublicID: readOnly.publicID,
                    permission: "read-only"
                )
            )
        }

        XCTAssertEqual(exporter.importedHerdIDs, [])
        XCTAssertEqual(exporter.exportedHerdIDs, [])
    }

    func testPendingInvitationGateBlocksRepairBeforeBridgeMutationAuthorityIsGranted() async throws {
        let herd = makeScopeHerd(
            id: "74757575-7575-4575-8575-757575757575",
            name: "Pending invitation"
        )
        let inventory = ScopeInventory(herds: [herd])
        let observationRepository = ScopeSharingRepository(
            accessByHerdID: [
                herd.publicID: .ownerPrivateStore(participantCount: 1)
            ]
        )
        let mutationAuthorityRepository = ScopeSharingRepository(
            accessByHerdID: [
                herd.publicID: HerdSharingAccess
                    .ownerPrivateStore(participantCount: 1)
                    .applyingCreationState(.pendingBridgeOperation)
            ]
        )
        let exporter = ScopeExporter(
            preflightByHerdID: [
                herd.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "pending-invitation-baseline",
                    recordIdentities: [
                        PublicIDRepairBridgeRecordIdentity(
                            step: .animals,
                            publicID: scopeOriginalID
                        )
                    ]
                )
            ]
        )
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: observationRepository,
            mutationAuthorityRepository: mutationAuthorityRepository,
            storageMode: .iCloud,
            exporter: exporter
        )
        let report = affectedScopeReport(herdID: herd.publicID)

        let preparation = try await coordinator.prepareForRepair()

        do {
            _ = try await coordinator.validateMutationAuthority(
                preparation: preparation,
                report: report
            )
            XCTFail("Expected pending accepted-invitation recovery to block repair authority")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(
                error,
                .sharingRecoveryRequired(
                    herdPublicID: herd.publicID,
                    state: "Resolve Sharing State"
                )
            )
        }

        do {
            try await coordinator.convergeAfterRepair(
                preparation: preparation,
                report: report
            )
            XCTFail("Expected convergence to recheck pending accepted-invitation recovery")
        } catch let error as PublicIDRepairBridgeError {
            XCTAssertEqual(
                error,
                .sharingRecoveryRequired(
                    herdPublicID: herd.publicID,
                    state: "Resolve Sharing State"
                )
            )
        }

        XCTAssertEqual(exporter.importedHerdIDs, [])
        XCTAssertEqual(exporter.exportedHerdIDs, [])
    }

    func testReadOnlyBridgeAlreadyAtManifestFinalIdentityDoesNotBecomeExportTarget() async throws {
        let readOnly = makeScopeHerd(
            id: "76767676-7676-4676-8676-767676767676",
            name: "Already repaired read only"
        )
        let inventory = ScopeInventory(herds: [readOnly])
        let repository = ScopeSharingRepository(
            accessByHerdID: [
                readOnly.publicID: .acceptedSharedStore(
                    permission: .readOnly,
                    participantCount: 2
                )
            ]
        )
        let exporter = ScopeExporter(
            preflightByHerdID: [
                readOnly.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "readonly-final",
                    recordIdentities: [
                        PublicIDRepairBridgeRecordIdentity(
                            step: .animals,
                            publicID: scopeReplacementID
                        )
                    ]
                )
            ]
        )
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: repository,
            storageMode: .iCloud,
            exporter: exporter
        )
        let report = affectedScopeReport(herdID: readOnly.publicID)
        let preparation = try await coordinator.prepareForRepair()

        _ = try await coordinator.validateMutationAuthority(
            preparation: preparation,
            report: report
        )
        try await coordinator.convergeAfterRepair(
            preparation: preparation,
            report: report
        )

        XCTAssertEqual(exporter.importedHerdIDs, [])
        XCTAssertEqual(exporter.exportedHerdIDs, [])
        XCTAssertGreaterThanOrEqual(exporter.preflightCallCountByHerdID[readOnly.publicID] ?? 0, 2)
    }
}

private let scopeOriginalID = UUID(uuidString: "74747474-7474-4474-8474-747474747474")!
private let scopeReplacementID = UUID(uuidString: "75757575-7575-4575-8575-757575757575")!

private func makeScopeHerd(id: String, name: String) -> HerdSummary {
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    return HerdSummary(
        publicID: UUID(uuidString: id)!,
        name: name,
        createdAt: timestamp,
        updatedAt: timestamp,
        schemaVersion: 1
    )
}

private func affectedScopeReport(herdID: UUID) -> PublicIDRepairReport {
    PublicIDRepairReport(
        completedAt: .now,
        assessment: PublicIDRepairAssessment(scannedAt: .now, entities: []),
        replacements: [
            PublicIDRepairReplacement(
                entityType: .animal,
                recordDescription: "Affected animal",
                stableRecordIdentifier: "scope-animal",
                retainedPublicID: scopeOriginalID,
                replacementPublicID: scopeReplacementID,
                owningHerdPublicID: herdID
            )
        ],
        referenceUpdates: [],
        backupFilename: "scope.json",
        backupPath: "/tmp/scope.json",
        validationIssueCount: 0
    )
}

private actor ScopeInventory: PublicIDRepairHerdInventoryReading {
    let herds: [HerdSummary]

    init(herds: [HerdSummary]) {
        self.herds = herds
    }

    func fetchHerds() async throws -> [HerdSummary] { herds }
}

@MainActor
private final class ScopeSharingRepository: HerdSharingRepository {
    let accessByHerdID: [UUID: HerdSharingAccess]

    init(accessByHerdID: [UUID: HerdSharingAccess]) {
        self.accessByHerdID = accessByHerdID
    }

    func fetchSharingReadiness(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) -> HerdSharingReadiness { .sharingAdapterAvailable }

    func fetchSharingAccess(
        for herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingAccess {
        guard let herd, let access = accessByHerdID[herd.publicID] else {
            throw ScopeTestError.missingAccess
        }
        return access
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw ScopeTestError.unexpectedMutation
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw ScopeTestError.unexpectedMutation
    }

    func importSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw ScopeTestError.unexpectedMutation
    }

    func acceptPreventedSharedDeletes(
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw ScopeTestError.unexpectedMutation
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw ScopeTestError.unexpectedMutation
    }

    func syncSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw ScopeTestError.unexpectedMutation
    }
}

@MainActor
private final class ScopeExporter: PublicIDRepairBridgeExporting {
    let preflightByHerdID: [UUID: PublicIDRepairBridgePreflight]
    private(set) var preflightCallCountByHerdID: [UUID: Int] = [:]
    private(set) var importedHerdIDs: [UUID] = []
    private(set) var exportedHerdIDs: [UUID] = []

    init(preflightByHerdID: [UUID: PublicIDRepairBridgePreflight]) {
        self.preflightByHerdID = preflightByHerdID
    }

    func captureBridgeFingerprint(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> String {
        guard let preflight = preflightByHerdID[herd.publicID] else {
            throw ScopeTestError.missingPreflight
        }
        return preflight.fingerprint
    }

    func captureBridgePreflight(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> PublicIDRepairBridgePreflight {
        preflightCallCountByHerdID[herd.publicID, default: 0] += 1
        guard let preflight = preflightByHerdID[herd.publicID] else {
            throw ScopeTestError.missingPreflight
        }
        return preflight
    }

    func importCurrentBridgeGraph(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        expectedFingerprint: String,
        report: PublicIDRepairReport
    ) async throws {
        guard preflightByHerdID[herd.publicID]?.fingerprint == expectedFingerprint else {
            throw ScopeTestError.fingerprintMismatch
        }
        importedHerdIDs.append(herd.publicID)
    }

    func exportRepairedGraph(
        for herd: HerdSummary,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws -> HerdSharingBridgeReconciliationReport {
        exportedHerdIDs.append(herd.publicID)
        return .empty
    }
}

@MainActor
private final class PreflightCapableBridgeStore: PublicIDRepairBridgeStore,
    PublicIDRepairBridgePreflightReading
{
    let preflight: PublicIDRepairBridgePreflight
    private(set) var preflightCallCount = 0
    private(set) var fingerprintCallCount = 0

    init(preflight: PublicIDRepairBridgePreflight) {
        self.preflight = preflight
    }

    func publicIDRepairPreflight(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation
    ) async throws -> PublicIDRepairBridgePreflight {
        preflightCallCount += 1
        return preflight
    }

    func publicIDRepairFingerprint(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation
    ) async throws -> String {
        fingerprintCallCount += 1
        return preflight.fingerprint
    }

    func importPublicIDRepairBridgeRecordsIntoSwiftData(
        for herd: HerdSummary,
        expectedLocation: HerdSharingAccess.BridgeLocation,
        expectedFingerprint: String,
        importer: any HerdSharingImportApplying,
        report: PublicIDRepairReport
    ) async throws -> HerdSharingBridgeImportResult {
        throw PreflightCapabilityTestError.unexpectedImport
    }

    func syncPublicIDRepairBridgeRecordsFromSnapshot(
        _ export: HerdSharingSwiftDataExport,
        expectedLocation: HerdSharingAccess.BridgeLocation,
        expectedFingerprint: String
    ) async throws -> HerdSharingBridgeExportResult {
        throw PreflightCapabilityTestError.unexpectedExport
    }
}

private enum ScopeTestError: Error {
    case missingAccess
    case missingPreflight
    case fingerprintMismatch
    case unexpectedMutation
}

private enum PreflightCapabilityTestError: Error {
    case unexpectedImport
    case unexpectedExport
}

@MainActor
extension PublicIDRepairBridgePreflightCapabilityTests {
    func testRepairPreparationObservesPhysicalBridgeWhenInventoryContainsDuplicateHerdIDs() async throws {
        let herdID = UUID(uuidString: "0A010101-0101-4101-8101-010101010101")!
        let first = makeHerdSummary(
            publicID: herdID,
            name: "Duplicate A",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let second = makeHerdSummary(
            publicID: herdID,
            name: "Duplicate B",
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let inventory = DuplicateHerdRepairInventory(herds: [first, second])
        let accessReader = RecordingPublicIDRepairBridgeAccessReader(
            access: .ownerPrivateStore(participantCount: 2, hasActiveSystemShare: true)
        )
        let observationRepository = PublicIDRepairBridgeObservationRepository(
            accessReader: accessReader
        )
        let exporter = DuplicateHerdRepairExporter(fingerprint: "duplicate-herd-baseline")
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: inventory,
            sharingRepository: observationRepository,
            storageMode: .iCloud,
            exporter: exporter
        )

        let preparation = try await coordinator.prepareForRepair()

        XCTAssertEqual(preparation.targets.count, 1)
        XCTAssertEqual(preparation.targets.first?.herdPublicID, herdID)
        XCTAssertEqual(preparation.targets.first?.location, .ownerPrivateStore)
        XCTAssertEqual(preparation.targets.first?.bridgeFingerprint, "duplicate-herd-baseline")
        XCTAssertEqual(accessReader.requestedHerdIDs, [herdID, herdID])
        XCTAssertEqual(exporter.preflightHerdIDs, [herdID])
    }

    func testRepairObservationReturnsPhysicalAccessWithoutCreationAuthorityAndRejectsMutations() async throws {
        let herd = makeHerdSummary(
            publicID: UUID(uuidString: "0A020202-0202-4202-8202-020202020202")!,
            name: "Observation only",
            createdAt: Date(timeIntervalSince1970: 3)
        )
        let accessReader = RecordingPublicIDRepairBridgeAccessReader(
            access: .acceptedSharedStore(permission: .readWrite, participantCount: 3)
                .applyingCreationState(.acceptedParticipantShare)
        )
        let repository = PublicIDRepairBridgeObservationRepository(accessReader: accessReader)

        let access = try await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)

        XCTAssertEqual(access.bridgeLocation, .acceptedSharedStore)
        XCTAssertEqual(access.permission, .readWrite)
        XCTAssertEqual(access.creationState, .unknown)

        do {
            _ = try await repository.startSharing(herd: herd, storageMode: .iCloud)
            XCTFail("The repair observation adapter must never create a share.")
        } catch let error as HerdSharingActionError {
            XCTAssertEqual(error, .sharingStateUnavailable)
        }
    }

    func testNormalDeferredSharingStillRejectsDuplicateLocalHerdRowsBeforeShareMutation() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let herdID = UUID(uuidString: "0A030303-0303-4303-8303-030303030303")!
        let first = Herd(
            publicID: herdID,
            name: "Duplicate local A",
            createdAt: Date(timeIntervalSince1970: 4),
            updatedAt: Date(timeIntervalSince1970: 5)
        )
        let second = Herd(
            publicID: herdID,
            name: "Duplicate local B",
            createdAt: Date(timeIntervalSince1970: 6),
            updatedAt: Date(timeIntervalSince1970: 7)
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let base = DuplicateHerdGuardedBaseRepository(access: .localOwnerBridgePending)
        let journal = HerdSharingBridgeJournal(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("HerdSharingSyncJournal.json")
        )
        let guardState = HerdSharingCreationStateGuard(
            context: context,
            journal: journal,
            ownershipRegistry: DuplicateHerdOwnershipRegistry(),
            accountOwnershipRegistry: DuplicateHerdAccountOwnershipRegistry()
        )
        let repository = DeferredCoreDataHerdSharingRepository(
            repository: base,
            creationGuard: guardState
        )
        let summary = first.toSummary()

        do {
            _ = try await repository.fetchSharingAccess(for: summary, storageMode: .iCloud)
            XCTFail("Normal sharing access must remain guarded when duplicate Herd rows exist.")
        } catch let error as HerdSharingActionError {
            guard case .bridgeConsistencyFailed = error else {
                return XCTFail("Expected bridgeConsistencyFailed, got \(error).")
            }
        }

        do {
            _ = try await repository.startSharing(herd: summary, storageMode: .iCloud)
            XCTFail("Duplicate Herd rows must prevent share creation.")
        } catch let error as HerdSharingActionError {
            guard case .bridgeConsistencyFailed = error else {
                return XCTFail("Expected bridgeConsistencyFailed, got \(error).")
            }
        }
        XCTAssertEqual(base.startSharingCallCount, 0)
    }

    private func makeHerdSummary(
        publicID: UUID,
        name: String,
        createdAt: Date
    ) -> HerdSummary {
        HerdSummary(
            publicID: publicID,
            name: name,
            createdAt: createdAt,
            updatedAt: createdAt.addingTimeInterval(1),
            schemaVersion: 1
        )
    }
}

private actor DuplicateHerdRepairInventory: PublicIDRepairHerdInventoryReading {
    let herds: [HerdSummary]

    init(herds: [HerdSummary]) {
        self.herds = herds
    }

    func fetchHerds() async throws -> [HerdSummary] { herds }
}

@MainActor
private final class RecordingPublicIDRepairBridgeAccessReader: PublicIDRepairBridgeAccessReading {
    let access: HerdSharingAccess
    private(set) var requestedHerdIDs: [UUID] = []

    init(access: HerdSharingAccess) {
        self.access = access
    }

    func fetchPublicIDRepairSharingAccess(for herd: HerdSummary) async throws -> HerdSharingAccess {
        requestedHerdIDs.append(herd.publicID)
        return access
    }
}

@MainActor
private final class DuplicateHerdRepairExporter: PublicIDRepairBridgeExporting {
    let fingerprint: String
    private(set) var preflightHerdIDs: [UUID] = []

    init(fingerprint: String) {
        self.fingerprint = fingerprint
    }

    func captureBridgeFingerprint(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> String {
        fingerprint
    }

    func captureBridgePreflight(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> PublicIDRepairBridgePreflight {
        preflightHerdIDs.append(herd.publicID)
        return PublicIDRepairBridgePreflight(
            fingerprint: fingerprint,
            recordIdentities: []
        )
    }

    func importCurrentBridgeGraph(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        expectedFingerprint: String,
        report: PublicIDRepairReport
    ) async throws {
        throw DuplicateHerdRepairTestError.unexpectedMutation
    }

    func exportRepairedGraph(
        for herd: HerdSummary,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws -> HerdSharingBridgeReconciliationReport {
        throw DuplicateHerdRepairTestError.unexpectedMutation
    }
}

@MainActor
private final class DuplicateHerdGuardedBaseRepository: HerdSharingRepository {
    let access: HerdSharingAccess
    private(set) var startSharingCallCount = 0

    init(access: HerdSharingAccess) {
        self.access = access
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
        access
    }

    func startSharing(
        herd: HerdSummary,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        startSharingCallCount += 1
        return HerdSharingActionResult(title: "Unexpected", message: "Unexpected")
    }

    func acceptShareInvitation(
        _ invitation: HerdShareInvitation,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw DuplicateHerdRepairTestError.unexpectedMutation
    }

    func importSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw DuplicateHerdRepairTestError.unexpectedMutation
    }

    func acceptPreventedSharedDeletes(
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw DuplicateHerdRepairTestError.unexpectedMutation
    }

    func restoreLocalFields(
        _ selections: [HerdSharingLocalFieldRestoreSelection],
        in review: HerdSharingConflictReview,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw DuplicateHerdRepairTestError.unexpectedMutation
    }

    func syncSharedBridgeData(
        herd: HerdSummary?,
        storageMode: HerdStorageMode
    ) async throws -> HerdSharingActionResult {
        throw DuplicateHerdRepairTestError.unexpectedMutation
    }
}

private final class DuplicateHerdOwnershipRegistry: HerdSharingOwnershipRecording {
    func ownership(for herdPublicID: UUID) -> HerdSharingOwnership? { nil }
    func recordOwner(herdPublicID: UUID, deviceID: String) {}
    func recordParticipant(herdPublicID: UUID) {}
    func clearOwnership(for herdPublicID: UUID) {}
}

private final class DuplicateHerdAccountOwnershipRegistry: HerdSharingAccountOwnershipRecording {
    func hasEstablishedOwnerShare(for herdPublicID: UUID) -> Bool { false }
    func recordEstablishedOwnerShare(for herdPublicID: UUID) {}
    func clearEstablishedOwnerShare(for herdPublicID: UUID) {}
}

private enum DuplicateHerdRepairTestError: Error {
    case unexpectedMutation
}
