import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class SwiftDataHerdSharingActorTests: XCTestCase {
  private enum InjectedFailure: Error, Equatable {
    case afterPersistentStoreCommit
  }

  func testLargeHerdExportIsPagedAndScopedToRequestedHerd() async throws {
    let container = try TestSupport.makeModelContainer()
    let fixture = try LargeHerdPersistenceFixture.insert(into: container.mainContext)
    let actor = SwiftDataHerdSharingActor(modelContainer: container)

    let export = try await actor.makeExport(
      for: fixture.herd,
      storeDescription: "large-herd test"
    )

    XCTAssertEqual(export.herd.publicID, fixture.herd.publicID)
    XCTAssertEqual(
      export.snapshot.records(for: .animals).count,
      fixture.expectedCounts.animals
    )
    XCTAssertEqual(
      export.snapshot.records(for: .animalTags).count,
      fixture.expectedCounts.animalTags
    )
    XCTAssertEqual(
      export.snapshot.records(for: .movements).count,
      fixture.expectedCounts.movements
    )
    XCTAssertEqual(
      export.snapshot.records(for: .healthRecords).count,
      fixture.expectedCounts.healthRecords
    )
    XCTAssertEqual(
      export.snapshot.records(for: .pregnancyChecks).count,
      fixture.expectedCounts.pregnancyChecks
    )
    XCTAssertEqual(
      export.snapshot.records(for: .workingSessions).count,
      fixture.expectedCounts.workingSessions
    )
    XCTAssertEqual(
      export.snapshot.records(for: .workingQueueItems).count,
      fixture.expectedCounts.workingQueueItems
    )
    XCTAssertEqual(
      export.snapshot.records(for: .workingTreatmentRecords).count,
      fixture.expectedCounts.workingTreatmentRecords
    )

    let exportedAnimalIDs = Set(export.localPublicIDs[.animals] ?? [])
    XCTAssertEqual(exportedAnimalIDs.count, fixture.expectedCounts.animals)
    XCTAssertFalse(exportedAnimalIDs.contains(fixture.firstExcludedAnimalPublicID))
  }

  func testConflictReportIsJournaledBeforePersistentStoreCommitFailure() async throws {
    let container = try TestSupport.makeModelContainer()
    let actor = SwiftDataHerdSharingActor(modelContainer: container)
    let herd = HerdSummary(
      publicID: UUID(),
      name: "Journal Boundary Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
    let snapshot = try HerdSharingBridgeExportSnapshotBuilder.makeExportStoreSnapshot(
      herd: herd,
      tagColorDefinitions: [],
      statusReferences: [],
      animalTags: [],
      pastureGroups: [],
      pastures: [],
      animals: [],
      movements: [],
      statusRecords: [],
      healthRecords: [],
      pregnancyChecks: [],
      workingProtocolTemplates: [],
      workingSessions: [],
      workingQueueItems: [],
      workingTreatmentRecords: [],
      fieldCheckSessions: [],
      fieldCheckAnimalChecks: [],
      fieldCheckFindings: [],
      storeDescription: "journal boundary test"
    )
    let conflictReport = makeConflictReport()
    let journalURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("yaHerd-\(#function)-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("journal.json")
    defer {
      try? FileManager.default.removeItem(at: journalURL.deletingLastPathComponent())
    }

    let journal = HerdSharingBridgeJournal(fileURL: journalURL)
    let coordinator = HerdSharingBridgeOperationCoordinator(journal: journal)
    let operation = try await coordinator.begin(
      herdPublicID: herd.publicID,
      direction: .importFromBridge,
      bridgeLocation: snapshot.storeDescription
    )
    let failureInjector = HerdSharingBridgeFailureInjector { step in
      step == .persistentStoreCommit ? InjectedFailure.afterPersistentStoreCommit : nil
    }

    do {
      let preparation = try await actor.prepareImport(
        snapshot,
        pendingConflictReport: conflictReport,
        failureInjector: failureInjector
      )
      try await coordinator.recordConflictReport(
        preparation.result.conflictReport,
        operationID: operation.id
      )
      _ = try await actor.commitImport(
        preparation,
        snapshot: snapshot,
        failureInjector: failureInjector
      )
      XCTFail("Expected failure after the persistent-store commit.")
    } catch {
      XCTAssertEqual(error as? InjectedFailure, .afterPersistentStoreCommit)
      await coordinator.fail(operationID: operation.id, error: error)
    }

    let retry = try await coordinator.begin(
      herdPublicID: herd.publicID,
      direction: .importFromBridge,
      bridgeLocation: snapshot.storeDescription
    )
    XCTAssertEqual(retry.pendingConflictReport, conflictReport)
  }

  private func makeConflictReport() -> HerdSharingBridgeConflictReport {
    HerdSharingBridgeConflictReport(
      existingLocalRecordUpdateCount: 1,
      updatedRecordConflicts: [
        HerdSharingBridgeConflictDetail(
          kind: .existingLocalRecordUpdate,
          sourceEntityName: SharedAnimalRecord.entityName,
          publicID: UUID(),
          localModifiedAt: Date(timeIntervalSince1970: 100),
          sharedModifiedAt: Date(timeIntervalSince1970: 200),
          fieldChanges: [
            HerdSharingBridgeFieldChange(
              fieldName: "name",
              localValue: HerdSharingBridgeConflictValue(
                type: .string,
                encodedValue: "Local value"
              ),
              sharedValue: HerdSharingBridgeConflictValue(
                type: .string,
                encodedValue: "Shared value"
              )
            )
          ]
        )
      ],
      preventedDeleteConflicts: []
    )
  }
}
