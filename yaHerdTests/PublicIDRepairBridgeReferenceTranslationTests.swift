import XCTest

@testable import yaHerd

final class PublicIDRepairBridgeReferenceTranslationTests: XCTestCase {
    func testUniqueBridgeRecordReferencesAreTranslatedToMappedReplacementID() throws {
        let herdID = UUID(uuidString: "D1111111-1111-4111-8111-111111111111")!
        let retainedAnimalID = UUID(uuidString: "D2222222-2222-4222-8222-222222222222")!
        let replacementAnimalID = UUID(uuidString: "D3333333-3333-4333-8333-333333333333")!
        let movementID = UUID(uuidString: "D4444444-4444-4444-8444-444444444444")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let bridge = HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdID,
            storeDescription: "duplicate bridge",
            recordsByStep: [
                .animals: [
                    animalSnapshot(
                        publicID: retainedAnimalID,
                        herdID: herdID,
                        name: "Alpha",
                        source: "alpha",
                        timestamp: timestamp
                    ),
                    animalSnapshot(
                        publicID: retainedAnimalID,
                        herdID: herdID,
                        name: "Beta",
                        source: "beta",
                        timestamp: timestamp
                    ),
                ],
                .movements: [
                    movementSnapshot(
                        publicID: movementID,
                        herdID: herdID,
                        animalID: retainedAnimalID,
                        source: "movement",
                        timestamp: timestamp
                    )
                ],
            ]
        )
        let local = HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdID,
            storeDescription: "repaired local",
            recordsByStep: [
                .animals: [
                    animalSnapshot(
                        publicID: retainedAnimalID,
                        herdID: herdID,
                        name: "Alpha",
                        source: "local-alpha",
                        timestamp: timestamp
                    ),
                    animalSnapshot(
                        publicID: replacementAnimalID,
                        herdID: herdID,
                        name: "Beta",
                        source: "local-beta",
                        timestamp: timestamp
                    ),
                ],
                .movements: [
                    movementSnapshot(
                        publicID: movementID,
                        herdID: herdID,
                        animalID: replacementAnimalID,
                        source: "local-movement",
                        timestamp: timestamp
                    )
                ],
            ]
        )

        let prepared = try bridge.preparingForPublicIDRepairImport(
            report: repairReport(
                timestamp: timestamp,
                retainedAnimalID: retainedAnimalID,
                replacementAnimalID: replacementAnimalID
            ),
            localRepairedSnapshot: local
        )

        XCTAssertEqual(
            Set(prepared.records(for: .animals).compactMap(\.parsedPublicID)),
            [retainedAnimalID, replacementAnimalID]
        )
        let movement = try XCTUnwrap(prepared.records(for: .movements).first)
        guard case .string(let translatedAnimalID) = movement.attributes["animalPublicID"] else {
            return XCTFail("Expected translated animalPublicID")
        }
        XCTAssertEqual(UUID(uuidString: translatedAnimalID), replacementAnimalID)
    }

    private func animalSnapshot(
        publicID: UUID,
        herdID: UUID,
        name: String,
        source: String,
        timestamp: Date
    ) -> HerdSharingBridgeRecordSnapshot {
        HerdSharingBridgeRecordSnapshot(
            entityName: SharedAnimalRecord.entityName,
            publicID: publicID.uuidString,
            sourceObjectURI: "yaherd-snapshot://\(source)",
            attributes: [
                "publicID": .string(publicID.uuidString),
                "herdPublicID": .string(herdID.uuidString),
                "name": .string(name),
                "lastMirroredAt": .date(timestamp),
            ]
        )
    }

    private func movementSnapshot(
        publicID: UUID,
        herdID: UUID,
        animalID: UUID,
        source: String,
        timestamp: Date
    ) -> HerdSharingBridgeRecordSnapshot {
        HerdSharingBridgeRecordSnapshot(
            entityName: SharedMovementRecord.entityName,
            publicID: publicID.uuidString,
            sourceObjectURI: "yaherd-snapshot://\(source)",
            attributes: [
                "publicID": .string(publicID.uuidString),
                "herdPublicID": .string(herdID.uuidString),
                "animalPublicID": .string(animalID.uuidString),
                "date": .date(timestamp),
                "lastMirroredAt": .date(timestamp),
            ]
        )
    }

    private func repairReport(
        timestamp: Date,
        retainedAnimalID: UUID,
        replacementAnimalID: UUID
    ) -> PublicIDRepairReport {
        PublicIDRepairReport(
            completedAt: timestamp,
            assessment: PublicIDRepairAssessment(
                scannedAt: timestamp,
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
                    stableRecordIdentifier: "animal|reference-translation",
                    retainedPublicID: retainedAnimalID,
                    replacementPublicID: replacementAnimalID
                )
            ],
            referenceUpdates: [],
            backupFilename: "reference-translation.json",
            backupPath: "/tmp/reference-translation.json",
            validationIssueCount: 0
        )
    }
}
