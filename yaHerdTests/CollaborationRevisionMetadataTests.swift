import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class CollaborationRevisionMetadataTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CollaborationRevisionRegistry.resetForTesting()
        CollaborationIdentityProvider.resetForTesting()
    }

    override func tearDown() {
        CollaborationRevisionRegistry.resetForTesting()
        CollaborationIdentityProvider.resetForTesting()
        super.tearDown()
    }

    func testPersistenceBoundaryCreatesAndIncrementsRevisionMetadata() throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let herd = Herd(name: "Revision Test Herd")
        context.insert(herd)

        try PersistenceLog.save(context, operation: "CollaborationRevisionMetadataTests.insert")

        var records = try context.fetch(FetchDescriptor<CollaborationRevisionRecord>())
        let key = CollaborationAggregateKey(type: .herd, publicID: herd.publicID)
        let inserted = try XCTUnwrap(records.first { $0.aggregateKey == key.storageKey })
        XCTAssertEqual(inserted.revision, 1)
        XCTAssertEqual(inserted.baseRevision, 0)
        XCTAssertFalse(inserted.modifiedByParticipantID.isEmpty)
        XCTAssertFalse(inserted.modifiedByDeviceID.isEmpty)
        let firstModifiedAt = inserted.modifiedAt

        herd.rename(to: "Renamed Revision Test Herd")
        try PersistenceLog.save(context, operation: "CollaborationRevisionMetadataTests.update")

        records = try context.fetch(FetchDescriptor<CollaborationRevisionRecord>())
        let updated = try XCTUnwrap(records.first { $0.aggregateKey == key.storageKey })
        XCTAssertEqual(updated.revision, 2)
        XCTAssertEqual(updated.baseRevision, 0)
        XCTAssertGreaterThan(updated.modifiedAt, firstModifiedAt)
        XCTAssertEqual(
            updated.metadata.currentFieldValues["name"]?.encodedValue,
            "Renamed Revision Test Herd"
        )
    }

    func testAtomicImportPreservesIncomingRevisionAndMakesItCommon() throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let herd = Herd(name: "Local Herd")
        context.insert(herd)
        try PersistenceLog.save(context, operation: "CollaborationRevisionMetadataTests.seed")

        herd.name = "Shared Herd"
        herd.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let key = CollaborationAggregateKey(type: .herd, publicID: herd.publicID)
        let currentFields = CollaborationFieldSnapshotProvider.snapshot(for: herd)
        let incoming = CollaborationRevisionMetadata(
            modifiedAt: herd.updatedAt,
            revision: 7,
            modifiedByParticipantID: "participant-remote",
            modifiedByDeviceID: "device-remote",
            baseRevision: 4,
            baseFieldValues: [:],
            currentFieldValues: currentFields,
            isDeleted: false
        )
        CollaborationRevisionRegistry.registerIncoming(incoming, for: key)

        try PersistenceLog.save(
            context,
            operation: "SwiftDataHerdSharingActor.atomicImport"
        )

        let records = try context.fetch(FetchDescriptor<CollaborationRevisionRecord>())
        let accepted = try XCTUnwrap(records.first { $0.aggregateKey == key.storageKey })
        XCTAssertEqual(accepted.revision, 7)
        XCTAssertEqual(accepted.baseRevision, 7)
        XCTAssertEqual(accepted.modifiedByParticipantID, "participant-remote")
        XCTAssertEqual(accepted.modifiedByDeviceID, "device-remote")
        XCTAssertEqual(accepted.metadata.baseFieldValues, currentFields)
        XCTAssertEqual(accepted.metadata.currentFieldValues, currentFields)
    }

    func testIncomingSnapshotReplacesEarlierHigherRevision() throws {
        let key = CollaborationAggregateKey(type: .animal, publicID: UUID())
        let olderExportValue = CollaborationRevisionMetadata(
            modifiedAt: Date(timeIntervalSince1970: 200),
            revision: 9,
            modifiedByParticipantID: "participant-local",
            modifiedByDeviceID: "device-local",
            baseRevision: 8,
            baseFieldValues: [:],
            currentFieldValues: [:],
            isDeleted: false
        )
        let currentSharedValue = CollaborationRevisionMetadata(
            modifiedAt: Date(timeIntervalSince1970: 100),
            revision: 3,
            modifiedByParticipantID: "participant-shared",
            modifiedByDeviceID: "device-shared",
            baseRevision: 2,
            baseFieldValues: [:],
            currentFieldValues: [:],
            isDeleted: false
        )

        CollaborationRevisionRegistry.registerIncoming(olderExportValue, for: key)
        CollaborationRevisionRegistry.registerIncoming(currentSharedValue, for: key)

        let registered = try XCTUnwrap(CollaborationRevisionRegistry.incomingMetadata(for: key))
        XCTAssertEqual(registered, currentSharedValue)
    }

    func testRevisionAnalysisRecognizesDisjointDivergentEdits() {
        let publicID = UUID()
        let key = CollaborationAggregateKey(type: .animal, publicID: publicID)
        let oldName = HerdSharingBridgeConflictValue(type: .string, encodedValue: "Original")
        let localName = HerdSharingBridgeConflictValue(type: .string, encodedValue: "Local")
        let oldTag = HerdSharingBridgeConflictValue(type: .string, encodedValue: "100")
        let sharedTag = HerdSharingBridgeConflictValue(type: .string, encodedValue: "200")
        let base: CollaborationFieldSnapshot = ["name": oldName, "tagNumber": oldTag]

        CollaborationRevisionRegistry.registerLocal(
            CollaborationRevisionMetadata(
                modifiedAt: Date(timeIntervalSince1970: 100),
                revision: 4,
                modifiedByParticipantID: "participant-local",
                modifiedByDeviceID: "device-local",
                baseRevision: 3,
                baseFieldValues: base,
                currentFieldValues: ["name": localName, "tagNumber": oldTag],
                isDeleted: false
            ),
            for: key
        )
        CollaborationRevisionRegistry.registerIncoming(
            CollaborationRevisionMetadata(
                modifiedAt: Date(timeIntervalSince1970: 200),
                revision: 5,
                modifiedByParticipantID: "participant-shared",
                modifiedByDeviceID: "device-shared",
                baseRevision: 3,
                baseFieldValues: base,
                currentFieldValues: ["name": oldName, "tagNumber": sharedTag],
                isDeleted: false
            ),
            for: key
        )

        let conflict = makeAnimalConflict(
            publicID: publicID,
            localName: localName,
            sharedName: oldName,
            localTag: oldTag,
            sharedTag: sharedTag
        )

        XCTAssertEqual(conflict.lastCommonRevision, 3)
        XCTAssertEqual(conflict.localRevision, 4)
        XCTAssertEqual(conflict.sharedRevision, 5)
        XCTAssertEqual(conflict.revisionComparison, .divergent)
        XCTAssertEqual(conflict.localChangedFields, ["name"])
        XCTAssertEqual(conflict.sharedChangedFields, ["tagNumber"])
        XCTAssertEqual(conflict.canMergeAutomatically, true)
        XCTAssertEqual(conflict.localModifiedByParticipantID, "participant-local")
        XCTAssertEqual(conflict.sharedModifiedByDeviceID, "device-shared")
    }

    func testEqualNextRevisionRecognizesConcurrentDisjointEdits() {
        let publicID = UUID()
        let key = CollaborationAggregateKey(type: .animal, publicID: publicID)
        let oldName = HerdSharingBridgeConflictValue(type: .string, encodedValue: "Original")
        let localName = HerdSharingBridgeConflictValue(type: .string, encodedValue: "Local")
        let oldTag = HerdSharingBridgeConflictValue(type: .string, encodedValue: "100")
        let sharedTag = HerdSharingBridgeConflictValue(type: .string, encodedValue: "200")
        let base: CollaborationFieldSnapshot = ["name": oldName, "tagNumber": oldTag]

        CollaborationRevisionRegistry.registerLocal(
            CollaborationRevisionMetadata(
                modifiedAt: Date(timeIntervalSince1970: 100),
                revision: 6,
                modifiedByParticipantID: "participant-local",
                modifiedByDeviceID: "device-local",
                baseRevision: 5,
                baseFieldValues: base,
                currentFieldValues: ["name": localName, "tagNumber": oldTag],
                isDeleted: false
            ),
            for: key
        )
        CollaborationRevisionRegistry.registerIncoming(
            CollaborationRevisionMetadata(
                modifiedAt: Date(timeIntervalSince1970: 200),
                revision: 6,
                modifiedByParticipantID: "participant-shared",
                modifiedByDeviceID: "device-shared",
                baseRevision: 5,
                baseFieldValues: base,
                currentFieldValues: ["name": oldName, "tagNumber": sharedTag],
                isDeleted: false
            ),
            for: key
        )

        let conflict = makeAnimalConflict(
            publicID: publicID,
            localName: localName,
            sharedName: oldName,
            localTag: oldTag,
            sharedTag: sharedTag
        )

        XCTAssertEqual(conflict.lastCommonRevision, 5)
        XCTAssertEqual(conflict.localRevision, 6)
        XCTAssertEqual(conflict.sharedRevision, 6)
        XCTAssertEqual(conflict.revisionComparison, .divergent)
        XCTAssertEqual(conflict.localChangedFields, ["name"])
        XCTAssertEqual(conflict.sharedChangedFields, ["tagNumber"])
        XCTAssertEqual(conflict.canMergeAutomatically, true)
    }

    func testCurrentBridgeModelAddsMetadataToEveryCollaborativeEntity() {
        let model = HerdSharingCoreDataModelFactory.makeCurrentModel()
        let entityNames = CollaborationAggregateType.allCases.map(\.rawValue)
            + [SharedDeletedRecord.entityName]
        let requiredAttributes = [
            "modifiedAt",
            "revision",
            "modifiedByParticipantID",
            "modifiedByDeviceID",
            "baseRevision",
            "baseFieldValuesJSON",
            "currentFieldValuesJSON",
        ]

        for entityName in entityNames {
            let entity = model.entitiesByName[entityName]
            XCTAssertNotNil(entity, "Missing bridge entity \(entityName)")
            for attributeName in requiredAttributes {
                XCTAssertNotNil(
                    entity?.attributesByName[attributeName],
                    "\(entityName) is missing \(attributeName)"
                )
            }
        }
    }

    private func makeAnimalConflict(
        publicID: UUID,
        localName: HerdSharingBridgeConflictValue,
        sharedName: HerdSharingBridgeConflictValue,
        localTag: HerdSharingBridgeConflictValue,
        sharedTag: HerdSharingBridgeConflictValue
    ) -> HerdSharingBridgeConflictDetail {
        HerdSharingBridgeConflictDetail(
            kind: .existingLocalRecordUpdate,
            sourceEntityName: CollaborationAggregateType.animal.rawValue,
            publicID: publicID,
            localModifiedAt: .distantPast,
            sharedModifiedAt: .distantPast,
            fieldChanges: [
                HerdSharingBridgeFieldChange(
                    fieldName: "name",
                    localValue: localName,
                    sharedValue: sharedName
                ),
                HerdSharingBridgeFieldChange(
                    fieldName: "tagNumber",
                    localValue: localTag,
                    sharedValue: sharedTag
                ),
            ]
        )
    }
}
