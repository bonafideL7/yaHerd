import XCTest

@testable import yaHerd

@MainActor
final class PublicIDRepairCrossHerdBridgeCollisionTests: XCTestCase {
    func testCrossHerdChildPublicIDCollisionRequiresChoiceBeforeAnyBridgeImport() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herdA = HerdSummary(
            publicID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            name: "Herd A",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let herdB = HerdSummary(
            publicID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            name: "Herd B",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let duplicatedAnimalID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let exporter = CrossHerdCollisionExporter(
            preflightByHerdID: [
                herdA.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "herd-a-baseline",
                    recordIdentities: [
                        PublicIDRepairBridgeRecordIdentity(
                            step: .animals,
                            publicID: duplicatedAnimalID
                        )
                    ]
                ),
                herdB.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "herd-b-baseline",
                    recordIdentities: [
                        PublicIDRepairBridgeRecordIdentity(
                            step: .animals,
                            publicID: duplicatedAnimalID
                        )
                    ]
                ),
            ]
        )
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: CrossHerdCollisionInventory(herds: [herdA, herdB]),
            sharingRepository: CrossHerdCollisionSharingRepository(),
            storageMode: .iCloud,
            exporter: exporter
        )

        let preparation = try await coordinator.prepareForRepair()

        do {
            try await coordinator.convergeAfterRepair(
                preparation: preparation,
                report: crossHerdCollisionReport()
            )
            XCTFail("Expected cross-Herd child ID collision to block convergence")
        } catch let error as PublicIDRepairBridgeResolutionRequired {
            XCTAssertEqual(error.issues.count, 1)
            let issue = try XCTUnwrap(error.issues.first)
            XCTAssertEqual(issue.kind, .bridgeRecordOwner)
            XCTAssertEqual(issue.entityType, .animal)
            XCTAssertEqual(issue.referencedPublicID, duplicatedAnimalID)
            XCTAssertEqual(issue.fieldName, "sharedBridgeOwner")
            XCTAssertEqual(issue.candidates.count, 2)
            XCTAssertEqual(
                Set(issue.candidates.compactMap(\.resultingPublicID)),
                Set([herdA.publicID, herdB.publicID])
            )
        }

        XCTAssertEqual(
            exporter.preflightedHerdIDs,
            [herdA.publicID, herdB.publicID, herdA.publicID, herdB.publicID],
            "Preparation and convergence both observe every bridge before collision ownership is decided"
        )
        XCTAssertEqual(exporter.importedHerdIDs, [])
        XCTAssertEqual(exporter.exportedHerdIDs, [])
    }

    func testEstablishedBridgeCollisionResolutionNarrowsRetryToDurableOwner() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herdA = HerdSummary(
            publicID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            name: "Herd A",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let herdB = HerdSummary(
            publicID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            name: "Herd B",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let duplicatedAnimalID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let exporter = CrossHerdCollisionExporter(
            preflightByHerdID: [
                herdA.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "herd-a-baseline",
                    recordIdentities: [
                        PublicIDRepairBridgeRecordIdentity(
                            step: .animals,
                            publicID: duplicatedAnimalID
                        )
                    ]
                ),
                herdB.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "herd-b-baseline",
                    recordIdentities: [
                        PublicIDRepairBridgeRecordIdentity(
                            step: .animals,
                            publicID: duplicatedAnimalID
                        )
                    ]
                ),
            ]
        )
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: CrossHerdCollisionInventory(herds: [herdA, herdB]),
            sharingRepository: CrossHerdCollisionSharingRepository(),
            storageMode: .iCloud,
            exporter: exporter
        )
        let preparation = try await coordinator.prepareForRepair()
        let initialError: PublicIDRepairBridgeResolutionRequired
        do {
            try await coordinator.convergeAfterRepair(
                preparation: preparation,
                report: crossHerdCollisionReport()
            )
            XCTFail("Expected unresolved bridge ownership")
            return
        } catch let error as PublicIDRepairBridgeResolutionRequired {
            initialError = error
        }
        let issue = try XCTUnwrap(initialError.issues.first)
        let selected = try XCTUnwrap(
            issue.candidates.first { $0.resultingPublicID == herdA.publicID }
        )
        let report = PublicIDRepairReport(
            completedAt: .now,
            assessment: PublicIDRepairAssessment(scannedAt: .now, entities: []),
            replacements: [],
            referenceUpdates: [],
            backupFilename: "cross-herd-collision.json",
            backupPath: "/tmp/cross-herd-collision.json",
            validationIssueCount: 0,
            bridgeCollisionResolutions: [
                PublicIDRepairBridgeCollisionResolution(
                    entityType: .animal,
                    retainedPublicID: duplicatedAnimalID,
                    selectedHerdPublicID: herdA.publicID,
                    herdPublicIDs: [herdA.publicID, herdB.publicID]
                )
            ]
        )

        do {
            try await coordinator.convergeAfterRepair(
                preparation: preparation,
                report: report
            )
            XCTFail("The original collision remains visible until the bridge mapping is replayed")
        } catch let error as PublicIDRepairBridgeResolutionRequired {
            let retryIssue = try XCTUnwrap(error.issues.first)
            XCTAssertEqual(retryIssue.candidates.count, 1)
            XCTAssertEqual(
                retryIssue.candidates.first?.stableRecordIdentifier,
                selected.stableRecordIdentifier
            )
            XCTAssertEqual(retryIssue.candidates.first?.resultingPublicID, herdA.publicID)
        }
    }

    func testLiveLocalOwnerNarrowsBridgeCollisionWithoutUserGuessing() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herdA = HerdSummary(
            publicID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            name: "Herd A",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let herdB = HerdSummary(
            publicID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            name: "Herd B",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let duplicatedAnimalID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let collisionIdentity = PublicIDRepairBridgeRecordIdentity(
            step: .animals,
            publicID: duplicatedAnimalID
        )
        let exporter = CrossHerdCollisionExporter(
            preflightByHerdID: [
                herdA.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "herd-a-baseline",
                    recordIdentities: [collisionIdentity],
                    localRecordIdentities: [collisionIdentity]
                ),
                herdB.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "herd-b-baseline",
                    recordIdentities: [collisionIdentity],
                    localRecordIdentities: []
                ),
            ]
        )
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: CrossHerdCollisionInventory(herds: [herdA, herdB]),
            sharingRepository: CrossHerdCollisionSharingRepository(),
            storageMode: .iCloud,
            exporter: exporter
        )

        let preparation = try await coordinator.prepareForRepair()
        do {
            try await coordinator.convergeAfterRepair(
                preparation: preparation,
                report: crossHerdCollisionReport()
            )
            XCTFail("Expected bridge collision replay decision")
        } catch let error as PublicIDRepairBridgeResolutionRequired {
            let issue = try XCTUnwrap(error.issues.first)
            XCTAssertEqual(issue.candidates.count, 1)
            XCTAssertEqual(issue.candidates.first?.resultingPublicID, herdA.publicID)
        }
    }

    func testManifestCollisionMappingIsAuthoritativeForBridgeReplay() throws {
        let retainedHerdID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let replacementHerdID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let retainedAnimalID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let replacementAnimalID = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!
        let report = PublicIDRepairReport(
            completedAt: .now,
            assessment: PublicIDRepairAssessment(scannedAt: .now, entities: []),
            replacements: [],
            referenceUpdates: [],
            backupFilename: "manifest-authority.json",
            backupPath: "/tmp/manifest-authority.json",
            validationIssueCount: 0,
            manifest: PublicIDRepairManifest(
                generations: [
                    PublicIDRepairManifestGeneration(
                        number: 1,
                        capturedAt: .now,
                        backup: nil,
                        recordMappings: [
                            PublicIDRepairManifestRecordMapping(
                                entityType: .animal,
                                originalPublicID: retainedAnimalID,
                                finalPublicID: retainedAnimalID,
                                owningHerdPublicID: retainedHerdID,
                                portableRecordIdentity: "bridge|retained",
                                recordFingerprint: nil,
                                recordDescription: "Retained shared animal",
                                retainedOriginalID: true,
                                origin: .bridgeCollision
                            ),
                            PublicIDRepairManifestRecordMapping(
                                entityType: .animal,
                                originalPublicID: retainedAnimalID,
                                finalPublicID: replacementAnimalID,
                                owningHerdPublicID: replacementHerdID,
                                portableRecordIdentity: "bridge|replacement",
                                recordFingerprint: nil,
                                recordDescription: "Replacement shared animal",
                                retainedOriginalID: false,
                                origin: .bridgeCollision
                            ),
                        ],
                        referenceTransformations: [],
                        selectedResolutionIDs: [],
                        bridgeRecoveryActions: [],
                        validationPassed: true
                    )
                ]
            )
        )
        let source = HerdSharingBridgeStoreSnapshot(
            herdPublicID: replacementHerdID,
            storeDescription: "manifest authority bridge",
            recordsByStep: [
                .animals: [
                    bridgeAnimalRecord(
                        publicID: retainedAnimalID,
                        herdPublicID: replacementHerdID,
                        name: "Replacement shared animal",
                        sourceURI: "bridge://animal/replacement"
                    ),
                ],
            ]
        )

        let mapped = try source.applyingPublicIDRepairBridgeCollisionResolutions(report: report)
        XCTAssertEqual(mapped.records(for: .animals).first?.parsedPublicID, replacementAnimalID)
    }

    func testLegacySplitLocalAndBridgeIdentityMigrationBlocksInsteadOfInventingThirdAuthority() throws {
        let retainedHerdID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let replacementHerdID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let retainedAnimalID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let localReplacementID = UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!
        let payload = LegacyPublicIDRepairReportPayload(
            completedAt: .now,
            assessment: PublicIDRepairAssessment(scannedAt: .now, entities: []),
            replacements: [
                PublicIDRepairReplacement(
                    entityType: .animal,
                    recordDescription: "Legacy local candidate",
                    stableRecordIdentifier: "animal|legacy-local-candidate",
                    retainedPublicID: retainedAnimalID,
                    replacementPublicID: localReplacementID
                )
            ],
            referenceUpdates: [],
            backupFilename: "legacy-split-identity.json",
            backupPath: "/tmp/legacy-split-identity.json",
            validationIssueCount: 0,
            bridgeCollisionResolutions: [
                LegacyCollisionPayload(
                    entityType: .animal,
                    retainedPublicID: retainedAnimalID,
                    selectedHerdPublicID: retainedHerdID,
                    herdPublicIDs: [retainedHerdID, replacementHerdID]
                )
            ]
        )

        let migrated = try JSONDecoder().decode(
            PublicIDRepairReport.self,
            from: JSONEncoder().encode(payload)
        )
        let bridgeReplacementID = try XCTUnwrap(
            migrated.bridgeCollisionResolutions?.first?.replacementPublicID(
                for: replacementHerdID
            )
        )

        XCTAssertNotEqual(localReplacementID, bridgeReplacementID)
        XCTAssertFalse(migrated.manifest.contradictions.isEmpty)
        XCTAssertFalse(migrated.validationPassed)
        XCTAssertTrue(
            migrated.manifest.contradictions.contains {
                $0.contains("Restore the retained pre-repair backup")
            }
        )

        let snapshot = HerdSharingBridgeStoreSnapshot(
            herdPublicID: replacementHerdID,
            storeDescription: "legacy split identity bridge",
            recordsByStep: [
                .animals: [
                    bridgeAnimalRecord(
                        publicID: retainedAnimalID,
                        herdPublicID: replacementHerdID,
                        name: "Legacy bridge animal",
                        sourceURI: "bridge://animal/legacy"
                    ),
                ],
            ]
        )
        XCTAssertThrowsError(
            try snapshot.applyingPublicIDRepairBridgeCollisionResolutions(report: migrated)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("contradictory durable identity"))
        }
    }

    func testSamePublicIDInDifferentEntityTypesDoesNotBlockConvergence() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herdA = HerdSummary(
            publicID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            name: "Herd A",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let herdB = HerdSummary(
            publicID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            name: "Herd B",
            createdAt: timestamp,
            updatedAt: timestamp,
            schemaVersion: 1
        )
        let sharedID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
        let exporter = CrossHerdCollisionExporter(
            preflightByHerdID: [
                herdA.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "herd-a-baseline",
                    recordIdentities: [
                        PublicIDRepairBridgeRecordIdentity(step: .animals, publicID: sharedID)
                    ]
                ),
                herdB.publicID: PublicIDRepairBridgePreflight(
                    fingerprint: "herd-b-baseline",
                    recordIdentities: [
                        PublicIDRepairBridgeRecordIdentity(step: .pastures, publicID: sharedID)
                    ]
                ),
            ]
        )
        let coordinator = DefaultPublicIDRepairBridgeCoordinator(
            herdInventory: CrossHerdCollisionInventory(herds: [herdA, herdB]),
            sharingRepository: CrossHerdCollisionSharingRepository(),
            storageMode: .iCloud,
            exporter: exporter
        )

        let preparation = try await coordinator.prepareForRepair()
        try await coordinator.convergeAfterRepair(
            preparation: preparation,
            report: crossHerdCollisionReport()
        )

        XCTAssertEqual(exporter.importedHerdIDs, [])
        XCTAssertEqual(exporter.exportedHerdIDs, [])
    }
}

private func bridgeAnimalRecord(
    publicID: UUID,
    herdPublicID: UUID,
    name: String,
    sourceURI: String
) -> HerdSharingBridgeRecordSnapshot {
    HerdSharingBridgeRecordSnapshot(
        entityName: SharedAnimalRecord.entityName,
        publicID: publicID.uuidString,
        sourceObjectURI: sourceURI,
        attributes: [
            "publicID": .string(publicID.uuidString),
            "herdPublicID": .string(herdPublicID.uuidString),
            "name": .string(name),
        ]
    )
}

private struct LegacyPublicIDRepairReportPayload: Encodable {
    let completedAt: Date
    let assessment: PublicIDRepairAssessment
    let replacements: [PublicIDRepairReplacement]
    let referenceUpdates: [PublicIDRepairReferenceUpdate]
    let backupFilename: String
    let backupPath: String
    let validationIssueCount: Int
    let bridgeCollisionResolutions: [LegacyCollisionPayload]
}

private struct LegacyCollisionPayload: Encodable {
    let entityType: PublicIDRepairEntityType
    let retainedPublicID: UUID
    let selectedHerdPublicID: UUID
    let herdPublicIDs: [UUID]
}

private func crossHerdCollisionReport() -> PublicIDRepairReport {
    PublicIDRepairReport(
        completedAt: .now,
        assessment: PublicIDRepairAssessment(scannedAt: .now, entities: []),
        replacements: [],
        referenceUpdates: [],
        backupFilename: "cross-herd-collision.json",
        backupPath: "/tmp/cross-herd-collision.json",
        validationIssueCount: 0
    )
}

private actor CrossHerdCollisionInventory: PublicIDRepairHerdInventoryReading {
    let herds: [HerdSummary]

    init(herds: [HerdSummary]) {
        self.herds = herds
    }

    func fetchHerds() async throws -> [HerdSummary] {
        herds
    }
}

@MainActor
private final class CrossHerdCollisionExporter: PublicIDRepairBridgeExporting {
    let preflightByHerdID: [UUID: PublicIDRepairBridgePreflight]
    private(set) var preflightedHerdIDs: [UUID] = []
    private(set) var importedHerdIDs: [UUID] = []
    private(set) var exportedHerdIDs: [UUID] = []

    init(preflightByHerdID: [UUID: PublicIDRepairBridgePreflight]) {
        self.preflightByHerdID = preflightByHerdID
    }

    func captureBridgeFingerprint(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> String {
        try preflight(for: herd).fingerprint
    }

    func captureBridgePreflight(
        for herd: HerdSummary,
        access: HerdSharingAccess
    ) async throws -> PublicIDRepairBridgePreflight {
        preflightedHerdIDs.append(herd.publicID)
        return try preflight(for: herd)
    }

    func importCurrentBridgeGraph(
        for herd: HerdSummary,
        access: HerdSharingAccess,
        expectedFingerprint: String,
        report: PublicIDRepairReport
    ) async throws {
        XCTAssertEqual(expectedFingerprint, try preflight(for: herd).fingerprint)
        importedHerdIDs.append(herd.publicID)
    }

    func exportRepairedGraph(
        for herd: HerdSummary,
        target: PublicIDRepairBridgeTargetIdentity
    ) async throws -> HerdSharingBridgeReconciliationReport {
        XCTAssertEqual(target.bridgeFingerprint, try preflight(for: herd).fingerprint)
        exportedHerdIDs.append(herd.publicID)
        return .empty
    }

    private func preflight(for herd: HerdSummary) throws -> PublicIDRepairBridgePreflight {
        guard let preflight = preflightByHerdID[herd.publicID] else {
            throw CrossHerdCollisionTestError.missingPreflight(herd.publicID)
        }
        return preflight
    }
}

private enum CrossHerdCollisionTestError: Error {
    case missingPreflight(UUID)
}

@MainActor
private final class CrossHerdCollisionSharingRepository: HerdSharingRepository {
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
