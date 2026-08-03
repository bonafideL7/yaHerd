import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class CollaborationRevisionImportTests: XCTestCase {
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

    func testOlderSharedImportCreatesMonotonicResolutionRevision() throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let herd = Herd(name: "Local Newer Herd")
        context.insert(herd)
        try PersistenceLog.save(context, operation: "CollaborationRevisionImportTests.seed")

        let key = CollaborationAggregateKey(type: .herd, publicID: herd.publicID)
        let records = try context.fetch(FetchDescriptor<CollaborationRevisionRecord>())
        let record = try XCTUnwrap(records.first { $0.aggregateKey == key.storageKey })
        let localFields = CollaborationFieldSnapshotProvider.snapshot(for: herd)
        let localMetadata = CollaborationRevisionMetadata(
            modifiedAt: Date(timeIntervalSince1970: 500),
            revision: 7,
            modifiedByParticipantID: "participant-local-previous",
            modifiedByDeviceID: "device-local-previous",
            baseRevision: 6,
            baseFieldValues: localFields,
            currentFieldValues: localFields,
            isDeleted: false
        )
        record.apply(localMetadata)
        try context.save()
        CollaborationRevisionRegistry.registerAuthoritativeLocal(localMetadata, for: key)

        herd.name = "Shared Older Herd"
        herd.updatedAt = Date(timeIntervalSince1970: 400)
        let importedFields = CollaborationFieldSnapshotProvider.snapshot(for: herd)
        let incoming = CollaborationRevisionMetadata(
            modifiedAt: herd.updatedAt,
            revision: 4,
            modifiedByParticipantID: "participant-remote",
            modifiedByDeviceID: "device-remote",
            baseRevision: 3,
            baseFieldValues: [:],
            currentFieldValues: importedFields,
            isDeleted: false
        )
        CollaborationRevisionRegistry.registerIncoming(incoming, for: key)
        let resolutionIdentity = CollaborationIdentityProvider.current()

        try PersistenceLog.save(
            context,
            operation: "SwiftDataHerdSharingActor.atomicImport"
        )

        let updatedRecords = try context.fetch(FetchDescriptor<CollaborationRevisionRecord>())
        let resolved = try XCTUnwrap(updatedRecords.first { $0.aggregateKey == key.storageKey })
        XCTAssertEqual(resolved.revision, 8)
        XCTAssertEqual(resolved.baseRevision, 4)
        XCTAssertEqual(resolved.modifiedByParticipantID, resolutionIdentity.participantID)
        XCTAssertEqual(resolved.modifiedByDeviceID, resolutionIdentity.deviceID)
        XCTAssertEqual(resolved.metadata.baseFieldValues, importedFields)
        XCTAssertEqual(resolved.metadata.currentFieldValues, importedFields)
    }
}
