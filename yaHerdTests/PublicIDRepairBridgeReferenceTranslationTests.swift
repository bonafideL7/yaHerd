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
                replacements: [
                    replacement(
                        entityType: .animal,
                        stableRecordIdentifier: "animal|reference-translation",
                        retainedID: retainedAnimalID,
                        replacementID: replacementAnimalID
                    )
                ]
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

    func testBridgeOnlyRecordReferencingRetainedDuplicateIDRequiresChoiceAndUsesSelection() throws {
        let herdID = UUID(uuidString: "A1111111-1111-4111-8111-111111111111")!
        let retainedAnimalID = UUID(uuidString: "A2222222-2222-4222-8222-222222222222")!
        let replacementAnimalID = UUID(uuidString: "A3333333-3333-4333-8333-333333333333")!
        let bridgeOnlyMovementID = UUID(uuidString: "A4444444-4444-4444-8444-444444444444")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let replacement = replacement(
            entityType: .animal,
            stableRecordIdentifier: "animal|bridge-only-ambiguous-reference",
            retainedID: retainedAnimalID,
            replacementID: replacementAnimalID
        )

        let bridge = HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdID,
            storeDescription: "bridge-only ambiguous reference",
            recordsByStep: [
                .animals: [
                    animalSnapshot(
                        publicID: retainedAnimalID,
                        herdID: herdID,
                        name: "Alpha",
                        source: "bridge-alpha",
                        timestamp: timestamp
                    ),
                    animalSnapshot(
                        publicID: retainedAnimalID,
                        herdID: herdID,
                        name: "Beta",
                        source: "bridge-beta",
                        timestamp: timestamp
                    ),
                ],
                .movements: [
                    movementSnapshot(
                        publicID: bridgeOnlyMovementID,
                        herdID: herdID,
                        animalID: retainedAnimalID,
                        source: "bridge-only-movement",
                        timestamp: timestamp
                    )
                ],
            ]
        )
        let local = HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdID,
            storeDescription: "repaired local without movement",
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
                ]
            ]
        )

        let issue: PublicIDRepairUnresolvedReference
        do {
            _ = try bridge.preparingForPublicIDRepairImport(
                report: repairReport(timestamp: timestamp, replacements: [replacement]),
                localRepairedSnapshot: local
            )
            return XCTFail("Expected bridge-only old-ID reference to require a deliberate choice")
        } catch let error as PublicIDRepairBridgeResolutionRequired {
            issue = try XCTUnwrap(error.issues.first)
        }

        XCTAssertEqual(issue.entityType, .movement)
        XCTAssertEqual(issue.fieldName, "animalPublicID")
        XCTAssertEqual(issue.referencedPublicID, retainedAnimalID)
        XCTAssertEqual(
            Set(issue.candidates.map(\.resultingPublicID)),
            [retainedAnimalID, replacementAnimalID]
        )
        let selected = try XCTUnwrap(
            issue.candidates.first { $0.resultingPublicID == replacementAnimalID }
        )
        let resolvedReport = repairReport(
            timestamp: timestamp,
            replacements: [replacement],
            referenceUpdates: [
                PublicIDRepairReferenceUpdate(
                    entityType: issue.entityType,
                    recordDescription: issue.recordDescription,
                    stableRecordIdentifier: issue.stableRecordIdentifier,
                    fieldName: issue.fieldName,
                    previousPublicID: issue.referencedPublicID,
                    repairedPublicID: selected.resultingPublicID
                )
            ]
        )

        let prepared = try bridge.preparingForPublicIDRepairImport(
            report: resolvedReport,
            localRepairedSnapshot: local
        )
        let movement = try XCTUnwrap(prepared.records(for: .movements).first)
        guard case .string(let translatedAnimalID) = movement.attributes["animalPublicID"] else {
            return XCTFail("Expected selected bridge-only animalPublicID")
        }
        XCTAssertEqual(UUID(uuidString: translatedAnimalID), replacementAnimalID)
    }

    func testBridgeOnlyRecordAlreadyUsingReplacementReferenceRemainsImportable() throws {
        let herdID = UUID(uuidString: "B1111111-1111-4111-8111-111111111111")!
        let retainedAnimalID = UUID(uuidString: "B2222222-2222-4222-8222-222222222222")!
        let replacementAnimalID = UUID(uuidString: "B3333333-3333-4333-8333-333333333333")!
        let bridgeOnlyMovementID = UUID(uuidString: "B4444444-4444-4444-8444-444444444444")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let bridge = HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdID,
            storeDescription: "bridge-only repaired reference",
            recordsByStep: [
                .animals: [
                    animalSnapshot(
                        publicID: retainedAnimalID,
                        herdID: herdID,
                        name: "Alpha",
                        source: "bridge-alpha",
                        timestamp: timestamp
                    ),
                    animalSnapshot(
                        publicID: retainedAnimalID,
                        herdID: herdID,
                        name: "Beta",
                        source: "bridge-beta",
                        timestamp: timestamp
                    ),
                ],
                .movements: [
                    movementSnapshot(
                        publicID: bridgeOnlyMovementID,
                        herdID: herdID,
                        animalID: replacementAnimalID,
                        source: "bridge-only-repaired-movement",
                        timestamp: timestamp
                    )
                ],
            ]
        )
        let local = HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdID,
            storeDescription: "repaired local without movement",
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
                ]
            ]
        )

        let prepared = try bridge.preparingForPublicIDRepairImport(
            report: repairReport(
                timestamp: timestamp,
                replacements: [
                    replacement(
                        entityType: .animal,
                        stableRecordIdentifier: "animal|bridge-only-repaired-reference",
                        retainedID: retainedAnimalID,
                        replacementID: replacementAnimalID
                    )
                ]
            ),
            localRepairedSnapshot: local
        )

        let movement = try XCTUnwrap(prepared.records(for: .movements).first)
        guard case .string(let animalID) = movement.attributes["animalPublicID"] else {
            return XCTFail("Expected bridge-only replacement reference")
        }
        XCTAssertEqual(UUID(uuidString: animalID), replacementAnimalID)
    }

    func testUUIDShapedFreeTextIsNotTreatedAsRepairReference() throws {
        let herdID = UUID(uuidString: "E1111111-1111-4111-8111-111111111111")!
        let retainedAnimalID = UUID(uuidString: "E2222222-2222-4222-8222-222222222222")!
        let replacementAnimalID = UUID(uuidString: "E3333333-3333-4333-8333-333333333333")!
        let healthID = UUID(uuidString: "E4444444-4444-4444-8444-444444444444")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let bridgeRecord = HerdSharingBridgeRecordSnapshot(
            entityName: SharedHealthRecord.entityName,
            publicID: healthID.uuidString,
            sourceObjectURI: "yaherd-snapshot://bridge-health",
            attributes: [
                "publicID": .string(healthID.uuidString),
                "herdPublicID": .string(herdID.uuidString),
                "animalPublicID": .string(retainedAnimalID.uuidString),
                "notes": .string(retainedAnimalID.uuidString),
                "lastMirroredAt": .date(timestamp),
            ]
        )
        let localRecord = HerdSharingBridgeRecordSnapshot(
            entityName: SharedHealthRecord.entityName,
            publicID: healthID.uuidString,
            sourceObjectURI: "yaherd-snapshot://local-health",
            attributes: [
                "publicID": .string(healthID.uuidString),
                "herdPublicID": .string(herdID.uuidString),
                "animalPublicID": .string(replacementAnimalID.uuidString),
                "notes": .string(replacementAnimalID.uuidString),
                "lastMirroredAt": .date(timestamp),
            ]
        )
        let bridge = HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdID,
            storeDescription: "free-text bridge",
            recordsByStep: [.healthRecords: [bridgeRecord]]
        )
        let local = HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdID,
            storeDescription: "free-text local",
            recordsByStep: [.healthRecords: [localRecord]]
        )

        let prepared = try bridge.preparingForPublicIDRepairImport(
            report: repairReport(
                timestamp: timestamp,
                replacements: [
                    replacement(
                        entityType: .animal,
                        stableRecordIdentifier: "animal|free-text",
                        retainedID: retainedAnimalID,
                        replacementID: replacementAnimalID
                    )
                ]
            ),
            localRepairedSnapshot: local
        )
        let preparedRecord = try XCTUnwrap(prepared.records(for: .healthRecords).first)
        guard case .string(let animalID) = preparedRecord.attributes["animalPublicID"],
              case .string(let notes) = preparedRecord.attributes["notes"] else {
            return XCTFail("Expected string attributes")
        }
        XCTAssertEqual(UUID(uuidString: animalID), replacementAnimalID)
        XCTAssertEqual(notes, retainedAnimalID.uuidString)
    }

    func testEmbeddedTreatmentItemIDsAndTreatmentReferencesUseRepairedIdentity() throws {
        let herdID = UUID(uuidString: "F1111111-1111-4111-8111-111111111111")!
        let sessionID = UUID(uuidString: "F2222222-2222-4222-8222-222222222222")!
        let treatmentRecordID = UUID(uuidString: "F3333333-3333-4333-8333-333333333333")!
        let retainedItemID = UUID(uuidString: "F4444444-4444-4444-8444-444444444444")!
        let replacementItemID = UUID(uuidString: "F5555555-5555-4555-8555-555555555555")!
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let bridgeItems = try JSONEncoder().encode([
            WorkingProtocolItem(id: retainedItemID, name: "Vaccine")
        ])
        let localItems = try JSONEncoder().encode([
            WorkingProtocolItem(id: replacementItemID, name: "Vaccine")
        ])

        let bridge = HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdID,
            storeDescription: "embedded item bridge",
            recordsByStep: [
                .workingSessions: [
                    HerdSharingBridgeRecordSnapshot(
                        entityName: SharedWorkingSessionRecord.entityName,
                        publicID: sessionID.uuidString,
                        sourceObjectURI: "yaherd-snapshot://bridge-session",
                        attributes: [
                            "publicID": .string(sessionID.uuidString),
                            "herdPublicID": .string(herdID.uuidString),
                            "protocolItemsJSON": .data(bridgeItems),
                            "lastMirroredAt": .date(timestamp),
                        ]
                    )
                ],
                .workingTreatmentRecords: [
                    HerdSharingBridgeRecordSnapshot(
                        entityName: SharedWorkingTreatmentRecord.entityName,
                        publicID: treatmentRecordID.uuidString,
                        sourceObjectURI: "yaherd-snapshot://bridge-treatment",
                        attributes: [
                            "publicID": .string(treatmentRecordID.uuidString),
                            "herdPublicID": .string(herdID.uuidString),
                            "treatmentItemID": .string(retainedItemID.uuidString),
                            "lastMirroredAt": .date(timestamp),
                        ]
                    )
                ],
            ]
        )
        let local = HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdID,
            storeDescription: "embedded item local",
            recordsByStep: [
                .workingSessions: [
                    HerdSharingBridgeRecordSnapshot(
                        entityName: SharedWorkingSessionRecord.entityName,
                        publicID: sessionID.uuidString,
                        sourceObjectURI: "yaherd-snapshot://local-session",
                        attributes: [
                            "publicID": .string(sessionID.uuidString),
                            "herdPublicID": .string(herdID.uuidString),
                            "protocolItemsJSON": .data(localItems),
                            "lastMirroredAt": .date(timestamp),
                        ]
                    )
                ],
                .workingTreatmentRecords: [
                    HerdSharingBridgeRecordSnapshot(
                        entityName: SharedWorkingTreatmentRecord.entityName,
                        publicID: treatmentRecordID.uuidString,
                        sourceObjectURI: "yaherd-snapshot://local-treatment",
                        attributes: [
                            "publicID": .string(treatmentRecordID.uuidString),
                            "herdPublicID": .string(herdID.uuidString),
                            "treatmentItemID": .string(replacementItemID.uuidString),
                            "lastMirroredAt": .date(timestamp),
                        ]
                    )
                ],
            ]
        )

        let prepared = try bridge.preparingForPublicIDRepairImport(
            report: repairReport(
                timestamp: timestamp,
                replacements: [
                    replacement(
                        entityType: .workingSession,
                        stableRecordIdentifier: "workingSession|\(sessionID.uuidString)|item-0",
                        retainedID: retainedItemID,
                        replacementID: replacementItemID
                    )
                ]
            ),
            localRepairedSnapshot: local
        )

        let session = try XCTUnwrap(prepared.records(for: .workingSessions).first)
        guard case .data(let translatedItemsData) = session.attributes["protocolItemsJSON"] else {
            return XCTFail("Expected translated protocolItemsJSON")
        }
        let translatedItems = try JSONDecoder().decode(
            [WorkingProtocolItem].self,
            from: translatedItemsData
        )
        XCTAssertEqual(translatedItems.map(\.id), [replacementItemID])

        let treatment = try XCTUnwrap(prepared.records(for: .workingTreatmentRecords).first)
        guard case .string(let translatedTreatmentItemID) = treatment.attributes["treatmentItemID"] else {
            return XCTFail("Expected translated treatmentItemID")
        }
        XCTAssertEqual(UUID(uuidString: translatedTreatmentItemID), replacementItemID)
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

    private func replacement(
        entityType: PublicIDRepairEntityType,
        stableRecordIdentifier: String,
        retainedID: UUID,
        replacementID: UUID
    ) -> PublicIDRepairReplacement {
        PublicIDRepairReplacement(
            entityType: entityType,
            recordDescription: "Repair regression",
            stableRecordIdentifier: stableRecordIdentifier,
            retainedPublicID: retainedID,
            replacementPublicID: replacementID
        )
    }

    private func repairReport(
        timestamp: Date,
        replacements: [PublicIDRepairReplacement],
        referenceUpdates: [PublicIDRepairReferenceUpdate] = []
    ) -> PublicIDRepairReport {
        PublicIDRepairReport(
            completedAt: timestamp,
            assessment: PublicIDRepairAssessment(
                scannedAt: timestamp,
                entities: []
            ),
            replacements: replacements,
            referenceUpdates: referenceUpdates,
            backupFilename: "reference-translation.json",
            backupPath: "/tmp/reference-translation.json",
            validationIssueCount: 0
        )
    }
}
