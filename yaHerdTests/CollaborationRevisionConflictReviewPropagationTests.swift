import XCTest

@testable import yaHerd

@MainActor
final class CollaborationRevisionConflictReviewPropagationTests: XCTestCase {
  override func setUp() {
    super.setUp()
    CollaborationRevisionRegistry.resetForTesting()
  }

  override func tearDown() {
    CollaborationRevisionRegistry.resetForTesting()
    super.tearDown()
  }

  func testBridgeRevisionAnalysisIsPersistedInConflictReviewRecord() throws {
    let publicID = UUID(uuidString: "00000000-0000-0000-0000-000000000034")!
    let key = CollaborationAggregateKey(
      sourceEntityName: "SharedAnimalRecord",
      publicID: publicID
    )
    let baseFields: CollaborationFieldSnapshot = [
      "name": HerdSharingBridgeConflictValue(type: .string, encodedValue: "Cow 12"),
      "tagNumber": HerdSharingBridgeConflictValue(type: .string, encodedValue: "12"),
    ]
    let localFields: CollaborationFieldSnapshot = [
      "name": HerdSharingBridgeConflictValue(type: .string, encodedValue: "Cow Twelve"),
      "tagNumber": HerdSharingBridgeConflictValue(type: .string, encodedValue: "12"),
    ]
    let sharedFields: CollaborationFieldSnapshot = [
      "name": HerdSharingBridgeConflictValue(type: .string, encodedValue: "Cow 12"),
      "tagNumber": HerdSharingBridgeConflictValue(type: .string, encodedValue: "14"),
    ]

    CollaborationRevisionRegistry.registerAuthoritativeLocal(
      CollaborationRevisionMetadata(
        modifiedAt: Date(timeIntervalSince1970: 30),
        revision: 2,
        modifiedByParticipantID: "local-participant",
        modifiedByDeviceID: "local-device",
        baseRevision: 1,
        baseFieldValues: baseFields,
        currentFieldValues: localFields,
        isDeleted: false
      ),
      for: key
    )
    CollaborationRevisionRegistry.registerIncoming(
      CollaborationRevisionMetadata(
        modifiedAt: Date(timeIntervalSince1970: 40),
        revision: 2,
        modifiedByParticipantID: "shared-participant",
        modifiedByDeviceID: "shared-device",
        baseRevision: 1,
        baseFieldValues: baseFields,
        currentFieldValues: sharedFields,
        isDeleted: false
      ),
      for: key
    )

    let bridgeConflict = HerdSharingBridgeConflictDetail(
      kind: .existingLocalRecordUpdate,
      sourceEntityName: "SharedAnimalRecord",
      publicID: publicID,
      localModifiedAt: Date(timeIntervalSince1970: 30),
      sharedModifiedAt: Date(timeIntervalSince1970: 40),
      fieldChanges: [
        HerdSharingBridgeFieldChange(
          fieldName: "name",
          localValue: HerdSharingBridgeConflictValue(
            type: .string,
            encodedValue: "Cow Twelve"
          ),
          sharedValue: HerdSharingBridgeConflictValue(
            type: .string,
            encodedValue: "Cow 12"
          )
        ),
        HerdSharingBridgeFieldChange(
          fieldName: "tagNumber",
          localValue: HerdSharingBridgeConflictValue(
            type: .string,
            encodedValue: "12"
          ),
          sharedValue: HerdSharingBridgeConflictValue(
            type: .string,
            encodedValue: "14"
          )
        ),
      ]
    )

    let conflict = CoreDataHerdSharingRepository.makeUpdatedRecordConflict(
      from: bridgeConflict
    )

    XCTAssertEqual(conflict.lastCommonRevision, 1)
    XCTAssertEqual(conflict.localRevision, 2)
    XCTAssertEqual(conflict.sharedRevision, 2)
    XCTAssertEqual(conflict.localBaseRevision, 1)
    XCTAssertEqual(conflict.sharedBaseRevision, 1)
    XCTAssertEqual(conflict.localModifiedByParticipantID, "local-participant")
    XCTAssertEqual(conflict.localModifiedByDeviceID, "local-device")
    XCTAssertEqual(conflict.sharedModifiedByParticipantID, "shared-participant")
    XCTAssertEqual(conflict.sharedModifiedByDeviceID, "shared-device")
    XCTAssertEqual(conflict.revisionComparison, .divergent)
    XCTAssertEqual(conflict.localChangedFields, ["name"])
    XCTAssertEqual(conflict.sharedChangedFields, ["tagNumber"])
    XCTAssertEqual(conflict.canMergeAutomatically, true)

    let encoded = try JSONEncoder().encode(conflict)
    let decoded = try JSONDecoder().decode(
      HerdSharingUpdatedRecordConflict.self,
      from: encoded
    )
    XCTAssertEqual(decoded, conflict)
  }

  func testLegacyConflictReviewDecodesWithoutRevisionAnalysis() throws {
    let json = """
    {
      "sourceEntityName": "SharedAnimalRecord",
      "publicID": "00000000-0000-0000-0000-000000000034",
      "localModifiedAt": 30,
      "sharedModifiedAt": 40,
      "fieldChanges": []
    }
    """.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    let conflict = try decoder.decode(
      HerdSharingUpdatedRecordConflict.self,
      from: json
    )

    XCTAssertNil(conflict.lastCommonRevision)
    XCTAssertNil(conflict.localRevision)
    XCTAssertNil(conflict.sharedRevision)
    XCTAssertNil(conflict.revisionComparison)
    XCTAssertNil(conflict.localChangedFields)
    XCTAssertNil(conflict.sharedChangedFields)
    XCTAssertNil(conflict.canMergeAutomatically)
  }
}
