//
//  HerdSharingConflictReviewTests.swift
//  yaHerdTests
//

import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingConflictReviewTests: XCTestCase {
  func testSummaryReportsExistingLocalUpdatesAndSkippedDeletes() {
    let review = HerdSharingConflictReview(
      title: "Shared-data conflicts detected",
      sourceDescription: "Manual import",
      detectedAt: Date(timeIntervalSince1970: 30),
      existingLocalRecordUpdateCount: 2,
      updatedRecordConflicts: [
        HerdSharingUpdatedRecordConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
          localModifiedAt: Date(timeIntervalSince1970: 20),
          sharedModifiedAt: Date(timeIntervalSince1970: 25)
        ),
        HerdSharingUpdatedRecordConflict(
          sourceEntityName: "SharedHealthRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
          localModifiedAt: Date(timeIntervalSince1970: 21),
          sharedModifiedAt: Date(timeIntervalSince1970: 26)
        ),
      ],
      preventedDeleteConflicts: [
        HerdSharingPreventedDeleteConflict(
          sourceEntityName: "SharedHealthRecord",
          publicID: UUID(),
          localModifiedAt: Date(timeIntervalSince1970: 20),
          sharedDeletedAt: Date(timeIntervalSince1970: 10)
        )
      ]
    )

    XCTAssertTrue(review.hasConflicts)
    XCTAssertEqual(review.updatedRecordConflictCount, 2)
    XCTAssertEqual(review.preventedDeleteCount, 1)
    XCTAssertEqual(
      review.summary,
      "2 existing local record(s) were updated from shared data; 1 shared delete(s) were skipped because local records appear newer."
    )
  }

  func testUpdatedRecordEntitySummariesSortByCountThenName() {
    let review = HerdSharingConflictReview(
      title: "Shared-data conflicts detected",
      sourceDescription: "Manual sync",
      detectedAt: Date(timeIntervalSince1970: 30),
      existingLocalRecordUpdateCount: 3,
      updatedRecordConflicts: [
        HerdSharingUpdatedRecordConflict(
          sourceEntityName: "SharedPastureRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          localModifiedAt: Date(timeIntervalSince1970: 20),
          sharedModifiedAt: Date(timeIntervalSince1970: 30)
        ),
        HerdSharingUpdatedRecordConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
          localModifiedAt: Date(timeIntervalSince1970: 21),
          sharedModifiedAt: Date(timeIntervalSince1970: 31)
        ),
        HerdSharingUpdatedRecordConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
          localModifiedAt: Date(timeIntervalSince1970: 22),
          sharedModifiedAt: Date(timeIntervalSince1970: 32)
        ),
      ],
      preventedDeleteConflicts: []
    )

    XCTAssertEqual(
      review.updatedRecordEntitySummaries,
      [
        HerdSharingUpdatedRecordEntitySummary(displayEntityName: "Animal", count: 2),
        HerdSharingUpdatedRecordEntitySummary(displayEntityName: "Pasture", count: 1),
      ]
    )
    XCTAssertEqual(
      review.recommendedAction,
      "Choose Accept Shared Updates if the imported shared values are correct. Keep local records only if the shared update was unexpected and you plan to re-export local values."
    )
  }

  func testDisplayEntityNameRemovesBridgePrefixes() {
    let conflict = HerdSharingPreventedDeleteConflict(
      sourceEntityName: "SharedPregnancyCheckRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 20),
      sharedDeletedAt: Date(timeIntervalSince1970: 10)
    )

    XCTAssertEqual(conflict.displayEntityName, "PregnancyCheck")
  }
  func testPreventedDeleteEntitySummariesSortByCountThenName() {
    let review = HerdSharingConflictReview(
      title: "Shared-data conflicts detected",
      sourceDescription: "Manual sync",
      detectedAt: Date(timeIntervalSince1970: 30),
      existingLocalRecordUpdateCount: 0,
      preventedDeleteConflicts: [
        HerdSharingPreventedDeleteConflict(
          sourceEntityName: "SharedPastureRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          localModifiedAt: Date(timeIntervalSince1970: 20),
          sharedDeletedAt: Date(timeIntervalSince1970: 10)
        ),
        HerdSharingPreventedDeleteConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
          localModifiedAt: Date(timeIntervalSince1970: 21),
          sharedDeletedAt: Date(timeIntervalSince1970: 11)
        ),
        HerdSharingPreventedDeleteConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
          localModifiedAt: Date(timeIntervalSince1970: 22),
          sharedDeletedAt: Date(timeIntervalSince1970: 12)
        ),
      ]
    )

    XCTAssertEqual(
      review.preventedDeleteEntitySummaries,
      [
        HerdSharingPreventedDeleteEntitySummary(displayEntityName: "Animal", count: 2),
        HerdSharingPreventedDeleteEntitySummary(displayEntityName: "Pasture", count: 1),
      ]
    )
    XCTAssertEqual(review.latestLocalModifiedAt, Date(timeIntervalSince1970: 22))
    XCTAssertEqual(review.earliestSharedDeletedAt, Date(timeIntervalSince1970: 10))
    XCTAssertEqual(
      review.recommendedAction,
      "Choose Keep Local Records to preserve local edits, or Accept Shared Deletes to delete the affected local records by public ID."
    )
  }

  func testUpdatedRecordConflictDecodesMissingFieldChangesAsEmpty() throws {
    let json = """
    {
      "sourceEntityName": "SharedAnimalRecord",
      "publicID": "00000000-0000-0000-0000-000000000004",
      "localModifiedAt": 20,
      "sharedModifiedAt": 30
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    let conflict = try decoder.decode(HerdSharingUpdatedRecordConflict.self, from: json)

    XCTAssertEqual(conflict.changedFieldCount, 0)
    XCTAssertTrue(conflict.fieldChanges.isEmpty)
  }

  func testUpdatedRecordConflictStoresFieldChanges() {
    let conflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedAnimalRecord",
      publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
      localModifiedAt: Date(timeIntervalSince1970: 20),
      sharedModifiedAt: Date(timeIntervalSince1970: 30),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "tagNumber",
          localValueDescription: "12",
          sharedValueDescription: "14"
        )
      ]
    )

    XCTAssertEqual(conflict.changedFieldCount, 1)
    XCTAssertEqual(conflict.fieldChanges.first?.fieldName, "tagNumber")
  }

  func testUpdatedRecordFieldChangeStoresTypedValues() throws {
    let change = HerdSharingUpdatedRecordFieldChange(
      fieldName: "updatedAt",
      localValue: .date(Date(timeIntervalSince1970: 20)),
      sharedValue: .date(Date(timeIntervalSince1970: 30))
    )

    XCTAssertEqual(change.localValue.type, .date)
    XCTAssertEqual(change.sharedValue.type, .date)
    XCTAssertEqual(change.localValue.displayType, "date")
    XCTAssertTrue(change.localValueDescription.contains("1970"))

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let data = try encoder.encode(change)
    let decoded = try JSONDecoder().decode(HerdSharingUpdatedRecordFieldChange.self, from: data)

    XCTAssertEqual(decoded, change)
    XCTAssertEqual(decoded.localValue.type, .date)
  }

  func testUpdatedRecordFieldChangeDecodesLegacyDisplayValuesAsStrings() throws {
    let json = """
    {
      "fieldName": "tagNumber",
      "localValueDescription": "12",
      "sharedValueDescription": "14"
    }
    """.data(using: .utf8)!

    let change = try JSONDecoder().decode(HerdSharingUpdatedRecordFieldChange.self, from: json)

    XCTAssertEqual(change.fieldName, "tagNumber")
    XCTAssertEqual(change.localValue.type, .string)
    XCTAssertEqual(change.localValueDescription, "12")
    XCTAssertEqual(change.sharedValueDescription, "14")
  }

  func testSupportedLocalFieldRestoreIncludesHealthMovementAndPregnancyScalars() {
    let healthConflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedHealthRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "treatment",
          localValue: .string("Local treatment"),
          sharedValue: .string("Shared treatment")
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "animalPublicID",
          localValue: .uuid(UUID()),
          sharedValue: .uuid(UUID())
        ),
      ]
    )

    XCTAssertEqual(
      healthConflict.supportedLocalRestoreFieldChanges.map(\.fieldName),
      ["treatment"]
    )

    let movementConflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedMovementRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "fromPasture",
          localValue: .string("North"),
          sharedValue: .string("South")
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "animalPublicID",
          localValue: .uuid(UUID()),
          sharedValue: .uuid(UUID())
        ),
      ]
    )

    XCTAssertEqual(
      movementConflict.supportedLocalRestoreFieldChanges.map(\.fieldName),
      ["fromPasture"]
    )

    let pregnancyConflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedPregnancyCheckRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "result",
          localValue: .string("pregnant"),
          sharedValue: .string("open")
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "sireAnimalPublicID",
          localValue: .uuid(UUID()),
          sharedValue: .uuid(UUID())
        ),
      ]
    )

    XCTAssertEqual(
      pregnancyConflict.supportedLocalRestoreFieldChanges.map(\.fieldName),
      ["result"]
    )
  }

  func testReviewOnlyFieldChangesExcludeSupportedRestoreFields() {
    let conflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedHealthRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "treatment",
          localValue: .string("Local treatment"),
          sharedValue: .string("Shared treatment")
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "animalPublicID",
          localValue: .uuid(UUID()),
          sharedValue: .uuid(UUID())
        ),
      ]
    )

    XCTAssertTrue(conflict.supportsLocalFieldRestore)
    XCTAssertTrue(conflict.hasReviewOnlyFieldChanges)
    XCTAssertEqual(conflict.supportedLocalRestoreFieldChanges.map(\.fieldName), ["treatment"])
    XCTAssertEqual(conflict.reviewOnlyFieldChanges.map(\.fieldName), ["animalPublicID"])
    XCTAssertEqual(conflict.relationshipFieldChanges.map(\.fieldName), ["animalPublicID"])
    XCTAssertTrue(conflict.complexFieldChanges.isEmpty)
    XCTAssertTrue(conflict.unsupportedFieldChanges.isEmpty)
  }

  func testSupportedLocalFieldRestoreIncludesStatusTagAndWorkingScalars() {
    let statusConflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedStatusRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "newStatus",
          localValue: .string("sold"),
          sharedValue: .string("active")
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "animalPublicID",
          localValue: .uuid(UUID()),
          sharedValue: .uuid(UUID())
        ),
      ]
    )

    XCTAssertEqual(statusConflict.supportedLocalRestoreFieldChanges.map(\.fieldName), ["newStatus"])
    XCTAssertEqual(statusConflict.reviewOnlyFieldChanges.map(\.fieldName), ["animalPublicID"])

    let tagConflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedAnimalTagRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "number",
          localValue: .string("12"),
          sharedValue: .string("14")
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "animalPublicID",
          localValue: .uuid(UUID()),
          sharedValue: .uuid(UUID())
        ),
      ]
    )

    XCTAssertEqual(tagConflict.supportedLocalRestoreFieldChanges.map(\.fieldName), ["number"])
    XCTAssertEqual(tagConflict.reviewOnlyFieldChanges.map(\.fieldName), ["animalPublicID"])

    let sessionConflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedWorkingSessionRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "protocolName",
          localValue: .string("Spring work"),
          sharedValue: .string("Fall work")
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "protocolItems",
          localValue: .string("[]"),
          sharedValue: .string("[]")
        ),
      ]
    )

    XCTAssertEqual(
      sessionConflict.supportedLocalRestoreFieldChanges.map(\.fieldName),
      ["protocolName"]
    )
    XCTAssertEqual(sessionConflict.reviewOnlyFieldChanges.map(\.fieldName), ["protocolItems"])
    XCTAssertEqual(sessionConflict.complexFieldChanges.map(\.fieldName), ["protocolItems"])

    let queueItemConflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedWorkingQueueItemRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "workNotes",
          localValue: .string("Local note"),
          sharedValue: .string("Shared note")
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "sessionPublicID",
          localValue: .uuid(UUID()),
          sharedValue: .uuid(UUID())
        ),
      ]
    )

    XCTAssertEqual(
      queueItemConflict.supportedLocalRestoreFieldChanges.map(\.fieldName),
      ["workNotes"]
    )
    XCTAssertEqual(queueItemConflict.reviewOnlyFieldChanges.map(\.fieldName), ["sessionPublicID"])
    XCTAssertEqual(queueItemConflict.relationshipFieldChanges.map(\.fieldName), ["sessionPublicID"])
  }

  func testSupportedLocalFieldRestoreIncludesRemainingScalarSharedEntities() {
    let tagColorConflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedTagColorDefinitionRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "name",
          localValue: .string("Yellow"),
          sharedValue: .string("Orange")
        )
      ]
    )

    XCTAssertEqual(tagColorConflict.supportedLocalRestoreFieldChanges.map(\.fieldName), ["name"])

    let pastureGroupConflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedPastureGroupRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "grazeDays",
          localValue: .int(7),
          sharedValue: .int(10)
        )
      ]
    )

    XCTAssertEqual(pastureGroupConflict.supportedLocalRestoreFieldChanges.map(\.fieldName), ["grazeDays"])

    let treatmentConflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedWorkingTreatmentRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "doseAmount",
          localValue: .double(2.0),
          sharedValue: .double(3.0)
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "doseUnit",
          localValue: .string(WorkingTreatmentDoseUnit.milliliter.rawValue),
          sharedValue: .string(WorkingTreatmentDoseUnit.milligram.rawValue)
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "administrationRoute",
          localValue: .string(WorkingTreatmentAdministrationRoute.subcutaneous.rawValue),
          sharedValue: .string(WorkingTreatmentAdministrationRoute.intramuscular.rawValue)
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "animalPublicID",
          localValue: .uuid(UUID()),
          sharedValue: .uuid(UUID())
        ),
      ]
    )

    XCTAssertEqual(
      treatmentConflict.supportedLocalRestoreFieldChanges.map(\.fieldName),
      ["doseAmount", "doseUnit", "administrationRoute"]
    )
    XCTAssertEqual(treatmentConflict.reviewOnlyFieldChanges.map(\.fieldName), ["animalPublicID"])
    XCTAssertEqual(treatmentConflict.relationshipFieldChanges.map(\.fieldName), ["animalPublicID"])

    let fieldCheckConflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedFieldCheckAnimalCheckRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "note",
          localValue: .string("Local note"),
          sharedValue: .string("Shared note")
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "sessionPublicID",
          localValue: .uuid(UUID()),
          sharedValue: .uuid(UUID())
        ),
      ]
    )

    XCTAssertEqual(fieldCheckConflict.supportedLocalRestoreFieldChanges.map(\.fieldName), ["note"])
    XCTAssertEqual(fieldCheckConflict.reviewOnlyFieldChanges.map(\.fieldName), ["sessionPublicID"])
    XCTAssertEqual(fieldCheckConflict.relationshipFieldChanges.map(\.fieldName), ["sessionPublicID"])
  }

  func testRelationshipComplexAndUnsupportedFieldCategories() {
    let conflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedAnimalRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: [
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "name",
          localValue: .string("Local"),
          sharedValue: .string("Shared")
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "pasturePublicID",
          localValue: .uuid(UUID()),
          sharedValue: .uuid(UUID())
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "distinguishingFeatures",
          localValue: .string("[]"),
          sharedValue: .string("[\"scar\"]")
        ),
        HerdSharingUpdatedRecordFieldChange(
          fieldName: "unknownField",
          localValue: .string("local"),
          sharedValue: .string("shared")
        ),
      ]
    )

    XCTAssertEqual(conflict.supportedLocalRestoreFieldChanges.map(\.fieldName), ["name"])
    XCTAssertEqual(conflict.relationshipFieldChanges.map(\.fieldName), ["pasturePublicID"])
    XCTAssertEqual(conflict.complexFieldChanges.map(\.fieldName), ["distinguishingFeatures"])
    XCTAssertEqual(conflict.unsupportedFieldChanges.map(\.fieldName), ["unknownField"])
    XCTAssertEqual(
      conflict.localFieldRestoreSupportCategory(for: conflict.fieldChanges[0]),
      .restorable
    )
    XCTAssertEqual(
      conflict.localFieldRestoreSupportCategory(for: conflict.fieldChanges[1]),
      .relationship
    )
    XCTAssertEqual(
      conflict.localFieldRestoreSupportCategory(for: conflict.fieldChanges[2]),
      .complex
    )
    XCTAssertEqual(
      conflict.localFieldRestoreSupportCategory(for: conflict.fieldChanges[3]),
      .unsupported
    )
  }

  func testKnownRelationshipFieldsRemainReviewOnly() {
    let relationshipFields = [
      "animalPublicID",
      "herdPublicID",
      "pasturePublicID",
      "workingSessionPublicID",
      "sireAnimalPublicID",
      "sourcePasturePublicID",
      "destinationPasturePublicID",
      "fieldCheckSessionPublicID",
    ]

    let conflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedWorkingQueueItemRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: relationshipFields.map { fieldName in
        HerdSharingUpdatedRecordFieldChange(
          fieldName: fieldName,
          localValue: .uuid(UUID()),
          sharedValue: .uuid(UUID())
        )
      }
    )

    XCTAssertTrue(conflict.supportedLocalRestoreFieldChanges.isEmpty)
    XCTAssertEqual(conflict.relationshipFieldChanges.map(\.fieldName), relationshipFields)
    XCTAssertTrue(conflict.complexFieldChanges.isEmpty)
    XCTAssertTrue(conflict.unsupportedFieldChanges.isEmpty)
  }

  func testKnownComplexFieldsRemainReviewOnly() {
    let complexFields = ["protocolItems", "distinguishingFeatures", "items"]

    let conflict = HerdSharingUpdatedRecordConflict(
      sourceEntityName: "SharedWorkingSessionRecord",
      publicID: UUID(),
      localModifiedAt: Date(timeIntervalSince1970: 10),
      sharedModifiedAt: Date(timeIntervalSince1970: 20),
      fieldChanges: complexFields.map { fieldName in
        HerdSharingUpdatedRecordFieldChange(
          fieldName: fieldName,
          localValue: .string("[]"),
          sharedValue: .string("[]")
        )
      }
    )

    XCTAssertTrue(conflict.supportedLocalRestoreFieldChanges.isEmpty)
    XCTAssertTrue(conflict.relationshipFieldChanges.isEmpty)
    XCTAssertEqual(conflict.complexFieldChanges.map(\.fieldName), complexFields)
    XCTAssertTrue(conflict.unsupportedFieldChanges.isEmpty)
  }

}
