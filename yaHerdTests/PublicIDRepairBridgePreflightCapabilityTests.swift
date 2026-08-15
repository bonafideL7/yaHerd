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
