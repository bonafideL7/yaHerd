import Foundation
import XCTest

@testable import yaHerd

final class PublicIDRepairHerdOwnershipPartitionTests: XCTestCase {
    func testExistingReplacementHerdChildIsNotImportedUnderRetainedHerd() throws {
        let retainedHerdID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let replacementHerdID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let animalID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

        let translatedBridge = HerdSharingBridgeStoreSnapshot(
            herdPublicID: retainedHerdID,
            storeDescription: "old shared bridge",
            recordsByStep: [
                .herd: [herdRecord(id: retainedHerdID, name: "My Herd")],
                .animals: [animalRecord(id: animalID, herdID: retainedHerdID, tagNumber: "202")],
            ]
        )
        let retainedLocal = HerdSharingBridgeStoreSnapshot(
            herdPublicID: retainedHerdID,
            storeDescription: "retained local",
            recordsByStep: [
                .herd: [herdRecord(id: retainedHerdID, name: "My Herd")],
            ]
        )
        let replacementLocal = HerdSharingBridgeStoreSnapshot(
            herdPublicID: replacementHerdID,
            storeDescription: "replacement local",
            recordsByStep: [
                .herd: [herdRecord(id: replacementHerdID, name: "My Herd")],
                .animals: [animalRecord(id: animalID, herdID: replacementHerdID, tagNumber: "202")],
            ]
        )

        let partitions = try translatedBridge.partitioningPublicIDRepairImportByLocalOwnership(
            localRepairedSnapshots: [retainedLocal, replacementLocal]
        )

        let retainedPartition = try XCTUnwrap(
            partitions.first { $0.herdPublicID == retainedHerdID }
        )
        let replacementPartition = try XCTUnwrap(
            partitions.first { $0.herdPublicID == replacementHerdID }
        )
        XCTAssertTrue(retainedPartition.records(for: .animals).isEmpty)
        let replacementAnimal = try XCTUnwrap(replacementPartition.records(for: .animals).first)
        XCTAssertEqual(replacementAnimal.parsedPublicID, animalID)
        XCTAssertEqual(
            replacementAnimal.attributes["herdPublicID"],
            .string(replacementHerdID.uuidString)
        )
        XCTAssertEqual(
            replacementPartition.records(for: .herd).first?.parsedPublicID,
            replacementHerdID
        )
    }

    func testBridgeOnlyChildUsesResolvedReferenceOwnerWhenRecordHasNoLocalMatch() throws {
        let retainedHerdID = UUID(uuidString: "31313131-3131-4131-8131-313131313131")!
        let replacementHerdID = UUID(uuidString: "32323232-3232-4232-8232-323232323232")!
        let retainedAnimalID = UUID(uuidString: "33333333-3333-4333-8333-333333333330")!
        let replacementAnimalID = UUID(uuidString: "34343434-3434-4434-8434-343434343434")!
        let movementID = UUID(uuidString: "35353535-3535-4535-8535-353535353535")!

        let translatedBridge = HerdSharingBridgeStoreSnapshot(
            herdPublicID: retainedHerdID,
            storeDescription: "translated shared bridge",
            recordsByStep: [
                .herd: [herdRecord(id: retainedHerdID, name: "My Herd")],
                .movements: [
                    movementRecord(
                        id: movementID,
                        herdID: retainedHerdID,
                        animalID: replacementAnimalID
                    )
                ],
            ]
        )
        let retainedLocal = HerdSharingBridgeStoreSnapshot(
            herdPublicID: retainedHerdID,
            storeDescription: "retained local",
            recordsByStep: [
                .herd: [herdRecord(id: retainedHerdID, name: "My Herd")],
                .animals: [
                    animalRecord(id: retainedAnimalID, herdID: retainedHerdID, tagNumber: "101")
                ],
            ]
        )
        let replacementLocal = HerdSharingBridgeStoreSnapshot(
            herdPublicID: replacementHerdID,
            storeDescription: "replacement local",
            recordsByStep: [
                .herd: [herdRecord(id: replacementHerdID, name: "My Herd")],
                .animals: [
                    animalRecord(id: replacementAnimalID, herdID: replacementHerdID, tagNumber: "202")
                ],
            ]
        )

        let partitions = try translatedBridge.partitioningPublicIDRepairImportByLocalOwnership(
            localRepairedSnapshots: [retainedLocal, replacementLocal]
        )

        let retainedPartition = try XCTUnwrap(
            partitions.first { $0.herdPublicID == retainedHerdID }
        )
        let replacementPartition = try XCTUnwrap(
            partitions.first { $0.herdPublicID == replacementHerdID }
        )
        XCTAssertTrue(retainedPartition.records(for: .movements).isEmpty)
        let movement = try XCTUnwrap(replacementPartition.records(for: .movements).first)
        XCTAssertEqual(movement.parsedPublicID, movementID)
        XCTAssertEqual(
            movement.attributes["herdPublicID"],
            .string(replacementHerdID.uuidString)
        )
        XCTAssertEqual(
            movement.attributes["animalPublicID"],
            .string(replacementAnimalID.uuidString)
        )
    }

    func testLookupDefinitionDoesNotClaimBridgeOnlyRecordOwnership() throws {
        let retainedHerdID = UUID(uuidString: "36363636-3636-4636-8636-363636363636")!
        let replacementHerdID = UUID(uuidString: "37373737-3737-4737-8737-373737373737")!
        let bridgeOnlyAnimalID = UUID(uuidString: "38383838-3838-4838-8838-383838383838")!
        let replacementColorID = UUID(uuidString: "39393939-3939-4939-8939-393939393939")!

        let translatedBridge = HerdSharingBridgeStoreSnapshot(
            herdPublicID: retainedHerdID,
            storeDescription: "translated shared bridge",
            recordsByStep: [
                .herd: [herdRecord(id: retainedHerdID, name: "Retained")],
                .animals: [
                    animalRecord(
                        id: bridgeOnlyAnimalID,
                        herdID: retainedHerdID,
                        tagNumber: "Bridge only",
                        tagColorID: replacementColorID
                    )
                ],
            ]
        )
        let retainedLocal = HerdSharingBridgeStoreSnapshot(
            herdPublicID: retainedHerdID,
            storeDescription: "retained local",
            recordsByStep: [
                .herd: [herdRecord(id: retainedHerdID, name: "Retained")],
            ]
        )
        let replacementLocal = HerdSharingBridgeStoreSnapshot(
            herdPublicID: replacementHerdID,
            storeDescription: "replacement local",
            recordsByStep: [
                .herd: [herdRecord(id: replacementHerdID, name: "Replacement")],
                .tagColorDefinitions: [
                    tagColorDefinitionRecord(id: replacementColorID, herdID: replacementHerdID)
                ],
            ]
        )

        let partitions = try translatedBridge.partitioningPublicIDRepairImportByLocalOwnership(
            localRepairedSnapshots: [retainedLocal, replacementLocal]
        )

        let retainedPartition = try XCTUnwrap(
            partitions.first { $0.herdPublicID == retainedHerdID }
        )
        XCTAssertEqual(
            retainedPartition.records(for: .animals).map(\.parsedPublicID),
            [bridgeOnlyAnimalID]
        )
        XCTAssertFalse(
            partitions.first { $0.herdPublicID == replacementHerdID }?
                .records(for: .animals).contains { $0.parsedPublicID == bridgeOnlyAnimalID } ?? false
        )
    }

    func testReferenceOnlyHerdCannotSelectCrossHerdTargetAndCanExplicitlyRemoveReference() throws {
        let sourceHerdID = UUID(uuidString: "3A3A3A3A-3A3A-4A3A-8A3A-3A3A3A3A3A3A")!
        let retainedOwnerHerdID = UUID(uuidString: "3B3B3B3B-3B3B-4B3B-8B3B-3B3B3B3B3B3B")!
        let replacementOwnerHerdID = UUID(uuidString: "3C3C3C3C-3C3C-4C3C-8C3C-3C3C3C3C3C3C")!
        let sourceAnimalID = UUID(uuidString: "3D3D3D3D-3D3D-4D3D-8D3D-3D3D3D3D3D3D")!
        let retainedSireID = UUID(uuidString: "3E3E3E3E-3E3E-4E3E-8E3E-3E3E3E3E3E3E")!
        let replacementSireID = UUID(uuidString: "3F3F3F3F-3F3F-4F3F-8F3F-3F3F3F3F3F3F")!

        let sourceBridgeAnimal = HerdSharingBridgeRecordSnapshot(
            entityName: SharedAnimalRecord.entityName,
            publicID: sourceAnimalID.uuidString,
            sourceObjectURI: "bridge://animal/reference-only",
            attributes: [
                "publicID": .string(sourceAnimalID.uuidString),
                "herdPublicID": .string(sourceHerdID.uuidString),
                "tagNumber": .string("Reference only"),
                "sireAnimalPublicID": .string(retainedSireID.uuidString),
            ]
        )
        let sourceBridge = HerdSharingBridgeStoreSnapshot(
            herdPublicID: sourceHerdID,
            storeDescription: "reference-only source bridge",
            recordsByStep: [
                .herd: [herdRecord(id: sourceHerdID, name: "Reference only")],
                .animals: [sourceBridgeAnimal],
            ]
        )
        let combinedLocal = HerdSharingBridgeStoreSnapshot(
            herdPublicID: sourceHerdID,
            storeDescription: "combined repaired local graph",
            recordsByStep: [
                .herd: [herdRecord(id: sourceHerdID, name: "Reference only")],
                .animals: [
                    animalRecord(
                        id: retainedSireID,
                        herdID: retainedOwnerHerdID,
                        tagNumber: "Retained sire"
                    ),
                    animalRecord(
                        id: replacementSireID,
                        herdID: replacementOwnerHerdID,
                        tagNumber: "Replacement sire"
                    ),
                ],
            ]
        )
        let replacement = PublicIDRepairReplacement(
            entityType: .animal,
            recordDescription: "Replacement sire",
            stableRecordIdentifier: "animal|replacement-sire",
            retainedPublicID: retainedSireID,
            replacementPublicID: replacementSireID,
            owningHerdPublicID: replacementOwnerHerdID,
            recordFingerprint: "replacement-fingerprint",
            retainedStableRecordIdentifier: "animal|retained-sire",
            retainedOwningHerdPublicID: retainedOwnerHerdID,
            retainedRecordFingerprint: "retained-fingerprint"
        )
        let baseReport = PublicIDRepairReport(
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            assessment: PublicIDRepairAssessment(
                scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
                entities: []
            ),
            replacements: [replacement],
            referenceUpdates: [],
            backupFilename: "reference-only.json",
            backupPath: "/tmp/reference-only.json",
            validationIssueCount: 0
        )

        let clearIssue: PublicIDRepairUnresolvedReference
        do {
            _ = try sourceBridge.preparingForPublicIDRepairImportWithInvalidReferenceRecovery(
                report: baseReport,
                localRepairedSnapshot: combinedLocal
            )
            XCTFail("Expected the reference-only Herd to require an explicit safe resolution")
            return
        } catch let required as PublicIDRepairBridgeResolutionRequired {
            clearIssue = try XCTUnwrap(required.issues.first)
        }

        XCTAssertEqual(clearIssue.fieldName, "sireAnimalPublicID")
        XCTAssertEqual(clearIssue.candidates.count, 1)
        XCTAssertEqual(
            clearIssue.candidates.first?.recordDescription,
            "Remove invalid shared reference"
        )
        XCTAssertFalse(
            clearIssue.candidates.contains {
                $0.resultingPublicID == replacementSireID
            }
        )

        let clearUpdate = PublicIDRepairReferenceUpdate(
            entityType: clearIssue.entityType,
            recordDescription: clearIssue.recordDescription,
            stableRecordIdentifier: clearIssue.stableRecordIdentifier,
            fieldName: clearIssue.fieldName,
            previousPublicID: clearIssue.referencedPublicID,
            repairedPublicID: clearIssue.referencedPublicID
        )
        let resolvedReport = PublicIDRepairReport(
            completedAt: baseReport.completedAt,
            assessment: baseReport.assessment,
            replacements: [replacement],
            referenceUpdates: [clearUpdate],
            backupFilename: baseReport.backupFilename,
            backupPath: baseReport.backupPath,
            validationIssueCount: 0
        )
        let prepared = try sourceBridge.preparingForPublicIDRepairImportWithInvalidReferenceRecovery(
            report: resolvedReport,
            localRepairedSnapshot: combinedLocal
        )
        let preparedSource = try XCTUnwrap(
            prepared.records(for: .animals).first { $0.parsedPublicID == sourceAnimalID }
        )
        XCTAssertEqual(preparedSource.attributes["sireAnimalPublicID"], .null)
        XCTAssertTrue(
            resolvedReport.manifest.referenceTransformations.contains {
                $0.sourcePortableRecordIdentity.hasPrefix("bridge-clear-reference|")
                    && $0.fieldName == "sireAnimalPublicID"
            }
        )
    }

    func testReplacementHerdTombstoneIsPartitionedWithItsRepairedOwner() throws {
        let retainedHerdID = UUID(uuidString: "41414141-4141-4141-8141-414141414141")!
        let replacementHerdID = UUID(uuidString: "42424242-4242-4242-8242-424242424242")!
        let animalID = UUID(uuidString: "43434343-4343-4343-8343-434343434343")!

        let translatedBridge = HerdSharingBridgeStoreSnapshot(
            herdPublicID: retainedHerdID,
            storeDescription: "old shared bridge",
            recordsByStep: [
                .herd: [herdRecord(id: retainedHerdID, name: "My Herd")],
                .deletions: [deletedAnimalRecord(id: animalID, herdID: retainedHerdID)],
            ]
        )
        let retainedLocal = HerdSharingBridgeStoreSnapshot(
            herdPublicID: retainedHerdID,
            storeDescription: "retained local",
            recordsByStep: [
                .herd: [herdRecord(id: retainedHerdID, name: "My Herd")],
            ]
        )
        let replacementLocal = HerdSharingBridgeStoreSnapshot(
            herdPublicID: replacementHerdID,
            storeDescription: "replacement local",
            recordsByStep: [
                .herd: [herdRecord(id: replacementHerdID, name: "My Herd")],
                .deletions: [deletedAnimalRecord(id: animalID, herdID: replacementHerdID)],
            ]
        )

        let partitions = try translatedBridge.partitioningPublicIDRepairImportByLocalOwnership(
            localRepairedSnapshots: [retainedLocal, replacementLocal]
        )

        let retainedPartition = try XCTUnwrap(
            partitions.first { $0.herdPublicID == retainedHerdID }
        )
        let replacementPartition = try XCTUnwrap(
            partitions.first { $0.herdPublicID == replacementHerdID }
        )
        XCTAssertTrue(retainedPartition.records(for: .deletions).isEmpty)
        let replacementDeletion = try XCTUnwrap(
            replacementPartition.records(for: .deletions).first
        )
        XCTAssertEqual(replacementDeletion.parsedPublicID, animalID)
        XCTAssertEqual(
            replacementDeletion.attributes["herdPublicID"],
            .string(replacementHerdID.uuidString)
        )
    }

    private func herdRecord(id: UUID, name: String) -> HerdSharingBridgeRecordSnapshot {
        HerdSharingBridgeRecordSnapshot(
            entityName: SharedHerdRecord.entityName,
            publicID: id.uuidString,
            sourceObjectURI: "bridge://herd/\(id.uuidString)",
            attributes: [
                "publicID": .string(id.uuidString),
                "name": .string(name),
                "lastMirroredAt": .date(Date(timeIntervalSince1970: 1_700_000_000)),
            ]
        )
    }

    private func animalRecord(
        id: UUID,
        herdID: UUID,
        tagNumber: String,
        tagColorID: UUID? = nil
    ) -> HerdSharingBridgeRecordSnapshot {
        var attributes: [String: HerdSharingBridgeAttributeValue] = [
            "publicID": .string(id.uuidString),
            "herdPublicID": .string(herdID.uuidString),
            "tagNumber": .string(tagNumber),
            "lastMirroredAt": .date(Date(timeIntervalSince1970: 1_700_000_000)),
        ]
        if let tagColorID {
            attributes["tagColorID"] = .string(tagColorID.uuidString)
        }
        return HerdSharingBridgeRecordSnapshot(
            entityName: SharedAnimalRecord.entityName,
            publicID: id.uuidString,
            sourceObjectURI: "bridge://animal/\(id.uuidString)",
            attributes: attributes
        )
    }

    private func tagColorDefinitionRecord(
        id: UUID,
        herdID: UUID
    ) -> HerdSharingBridgeRecordSnapshot {
        HerdSharingBridgeRecordSnapshot(
            entityName: SharedTagColorDefinitionRecord.entityName,
            publicID: id.uuidString,
            sourceObjectURI: "bridge://tag-color/\(id.uuidString)",
            attributes: [
                "publicID": .string(id.uuidString),
                "herdPublicID": .string(herdID.uuidString),
                "name": .string("Blue"),
                "lastMirroredAt": .date(Date(timeIntervalSince1970: 1_700_000_000)),
            ]
        )
    }

    private func movementRecord(
        id: UUID,
        herdID: UUID,
        animalID: UUID
    ) -> HerdSharingBridgeRecordSnapshot {
        HerdSharingBridgeRecordSnapshot(
            entityName: SharedMovementRecord.entityName,
            publicID: id.uuidString,
            sourceObjectURI: "bridge://movement/\(id.uuidString)",
            attributes: [
                "publicID": .string(id.uuidString),
                "herdPublicID": .string(herdID.uuidString),
                "animalPublicID": .string(animalID.uuidString),
                "lastMirroredAt": .date(Date(timeIntervalSince1970: 1_700_000_000)),
            ]
        )
    }

    private func deletedAnimalRecord(
        id: UUID,
        herdID: UUID
    ) -> HerdSharingBridgeRecordSnapshot {
        HerdSharingBridgeRecordSnapshot(
            entityName: SharedDeletedRecord.entityName,
            publicID: id.uuidString,
            sourceObjectURI: "bridge://deletion/\(id.uuidString)",
            attributes: [
                "publicID": .string(id.uuidString),
                "herdPublicID": .string(herdID.uuidString),
                "sourceEntityName": .string(SharedAnimalRecord.entityName),
                "lastMirroredAt": .date(Date(timeIntervalSince1970: 1_700_000_000)),
            ]
        )
    }
}
