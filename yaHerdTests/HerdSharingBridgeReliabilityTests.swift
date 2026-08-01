//
//  HerdSharingBridgeReliabilityTests.swift
//  yaHerdTests
//

import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingBridgeReliabilityTests: XCTestCase {
  private enum InjectedFailure: Error, Equatable {
    case afterStep(HerdSharingBridgeStep)
  }

  func testFailureInjectionRunsAfterEveryBridgeStep() async throws {
    for step in HerdSharingBridgeStep.allCases {
      let journalURL = temporaryJournalURL(testName: #function, suffix: step.rawValue)
      defer { try? FileManager.default.removeItem(at: journalURL.deletingLastPathComponent()) }

      let journal = HerdSharingBridgeJournal(fileURL: journalURL)
      let coordinator = HerdSharingBridgeOperationCoordinator(
        journal: journal,
        failureInjector: HerdSharingBridgeFailureInjector { candidate in
          candidate == step ? InjectedFailure.afterStep(candidate) : nil
        }
      )
      let operation = try await coordinator.begin(
        herdPublicID: UUID(),
        direction: .exportToBridge,
        bridgeLocation: "test bridge"
      )

      do {
        _ = try await coordinator.execute(step, operationID: operation.id) { () }
        XCTFail("Expected failure injection after \(step.rawValue)")
      } catch {
        XCTAssertEqual(error as? InjectedFailure, .afterStep(step))
      }
      await coordinator.fail(operationID: operation.id, error: InjectedFailure.afterStep(step))

      let unfinishedOperations = await journal.unfinishedOperations()
      let persistedOperation = try XCTUnwrap(unfinishedOperations.first)
      XCTAssertEqual(persistedOperation.completedSteps, [step])
      XCTAssertEqual(persistedOperation.state, .failed)
    }
  }

  func testRetryReusesIncompleteOperationAndWritesCheckpointOnlyAfterCompletion() async throws {
    let journalURL = temporaryJournalURL(testName: #function)
    defer { try? FileManager.default.removeItem(at: journalURL.deletingLastPathComponent()) }

    let herdID = UUID()
    let journal = HerdSharingBridgeJournal(fileURL: journalURL)
    let coordinator = HerdSharingBridgeOperationCoordinator(journal: journal)
    let firstAttempt = try await coordinator.begin(
      herdPublicID: herdID,
      direction: .importFromBridge,
      bridgeLocation: "owner private store"
    )
    _ = try await coordinator.execute(.herd, operationID: firstAttempt.id) { "herd" }
    await coordinator.fail(
      operationID: firstAttempt.id,
      error: InjectedFailure.afterStep(.herd)
    )

    let retry = try await coordinator.begin(
      herdPublicID: herdID,
      direction: .importFromBridge,
      bridgeLocation: "owner private store"
    )
    XCTAssertEqual(retry.id, firstAttempt.id)
    XCTAssertEqual(retry.attemptCount, 2)
    XCTAssertTrue(retry.completedSteps.isEmpty)

    _ = try await coordinator.execute(.herd, operationID: retry.id) { "herd" }
    try await coordinator.complete(
      operationID: retry.id,
      recordCounts: ["updatedRecords": 1],
      reconciliationSummary: "clean"
    )

    let reloadedJournal = HerdSharingBridgeJournal(fileURL: journalURL)
    let reloadedUnfinishedOperations = await reloadedJournal.unfinishedOperations()
    XCTAssertTrue(reloadedUnfinishedOperations.isEmpty)
    let checkpoint = await reloadedJournal.checkpoint(
      herdPublicID: herdID,
      direction: .importFromBridge,
      bridgeLocation: "owner private store"
    )
    XCTAssertEqual(checkpoint?.operationID, firstAttempt.id)
    XCTAssertEqual(checkpoint?.recordCounts["updatedRecords"], 1)
    XCTAssertEqual(checkpoint?.reconciliationSummary, "clean")
  }

  func testReconciliationReportsMissingAndDuplicatePublicIDs() throws {
    let sharedID = UUID()
    let localOnlyID = UUID()
    let bridgeOnlyID = UUID()
    let duplicateLocalID = UUID()
    let duplicateBridgeID = UUID()

    let report = HerdSharingBridgeReconciler.makeReport(
      localPublicIDs: [
        .animals: [sharedID, localOnlyID, duplicateLocalID, duplicateLocalID]
      ],
      bridgePublicIDs: [
        .animals: [sharedID, bridgeOnlyID, duplicateBridgeID, duplicateBridgeID]
      ],
      deletionTombstoneCount: 2
    )

    let animals = try XCTUnwrap(report.entities.first { $0.step == .animals })
    XCTAssertEqual(animals.missingInBridge, [localOnlyID, duplicateLocalID].sorted(by: uuidSort))
    XCTAssertEqual(
      animals.missingInSwiftData, [bridgeOnlyID, duplicateBridgeID].sorted(by: uuidSort))
    XCTAssertEqual(animals.duplicateLocalPublicIDs, [duplicateLocalID])
    XCTAssertEqual(animals.duplicateBridgePublicIDs, [duplicateBridgeID])
    XCTAssertEqual(report.deletionTombstoneCount, 2)
    XCTAssertTrue(report.hasUnresolvedDifferences)
  }

  func testInterruptedImportRetainsConflictSnapshotForRetry() async throws {
    let journalURL = temporaryJournalURL(testName: #function)
    defer { try? FileManager.default.removeItem(at: journalURL.deletingLastPathComponent()) }

    let publicID = UUID()
    let conflict = HerdSharingBridgeConflictDetail(
      kind: .existingLocalRecordUpdate,
      sourceEntityName: SharedAnimalRecord.entityName,
      publicID: publicID,
      localModifiedAt: Date(timeIntervalSince1970: 100),
      sharedModifiedAt: Date(timeIntervalSince1970: 200),
      fieldChanges: [
        HerdSharingBridgeFieldChange(
          fieldName: "name",
          localValue: HerdSharingBridgeConflictValue(type: .string, encodedValue: "Local"),
          sharedValue: HerdSharingBridgeConflictValue(type: .string, encodedValue: "Remote")
        )
      ]
    )
    let report = HerdSharingBridgeConflictReport(
      existingLocalRecordUpdateCount: 1,
      updatedRecordConflicts: [conflict],
      preventedDeleteConflicts: []
    )
    let journal = HerdSharingBridgeJournal(fileURL: journalURL)
    let coordinator = HerdSharingBridgeOperationCoordinator(journal: journal)
    let firstAttempt = try await coordinator.begin(
      herdPublicID: UUID(),
      direction: .importFromBridge,
      bridgeLocation: "owner private store"
    )
    try await coordinator.recordConflictReport(report, operationID: firstAttempt.id)
    await coordinator.fail(
      operationID: firstAttempt.id, error: InjectedFailure.afterStep(.persistentStoreCommit))

    let reloadedCoordinator = HerdSharingBridgeOperationCoordinator(
      journal: HerdSharingBridgeJournal(fileURL: journalURL)
    )
    let retry = try await reloadedCoordinator.begin(
      herdPublicID: firstAttempt.herdPublicID,
      direction: .importFromBridge,
      bridgeLocation: firstAttempt.bridgeLocation
    )
    XCTAssertEqual(retry.pendingConflictReport, report)

    let recovered = HerdSharingBridgeConflictReport.empty.recoveringMissingConflicts(
      from: retry.pendingConflictReport
    )
    XCTAssertEqual(recovered, report)
  }

  func testFreshConflictSnapshotReplacesRecoveredSnapshotForSameRecord() {
    let publicID = UUID()
    let interrupted = conflictReport(
      publicID: publicID,
      localName: "Old local",
      sharedName: "Old remote"
    )
    let fresh = conflictReport(
      publicID: publicID,
      localName: "New local",
      sharedName: "New remote"
    )

    let recovered = fresh.recoveringMissingConflicts(from: interrupted)

    XCTAssertEqual(recovered.updatedRecordConflicts.count, 1)
    XCTAssertEqual(
      recovered.updatedRecordConflicts.first?.fieldChanges.first?.localValue.encodedValue,
      "New local"
    )
  }

  func testOperationGateSerializesMutationsAcrossSuspensionPoints() async {
    let gate = HerdSharingBridgeOperationGate()
    await gate.acquire()

    var waiterStarted = false
    var waiterAcquired = false
    let waiter = Task { @MainActor in
      waiterStarted = true
      await gate.acquire()
      waiterAcquired = true
      gate.release()
    }

    for _ in 0..<20 where !waiterStarted {
      await Task.yield()
    }

    XCTAssertTrue(waiterStarted)
    XCTAssertFalse(waiterAcquired)

    gate.release()
    await waiter.value

    XCTAssertTrue(waiterAcquired)
  }

  func testDuplicateDetectionReturnsOnlyAmbiguousEntityIDs() {
    let duplicateAnimalID = UUID()
    let duplicates = HerdSharingBridgeReconciler.duplicatePublicIDs(
      in: [
        .animals: [duplicateAnimalID, duplicateAnimalID],
        .pastures: [UUID()],
      ]
    )

    XCTAssertEqual(duplicates, [.animals: [duplicateAnimalID]])
  }

  private func conflictReport(
    publicID: UUID,
    localName: String,
    sharedName: String
  ) -> HerdSharingBridgeConflictReport {
    HerdSharingBridgeConflictReport(
      existingLocalRecordUpdateCount: 1,
      updatedRecordConflicts: [
        HerdSharingBridgeConflictDetail(
          kind: .existingLocalRecordUpdate,
          sourceEntityName: SharedAnimalRecord.entityName,
          publicID: publicID,
          localModifiedAt: Date(timeIntervalSince1970: 100),
          sharedModifiedAt: Date(timeIntervalSince1970: 200),
          fieldChanges: [
            HerdSharingBridgeFieldChange(
              fieldName: "name",
              localValue: HerdSharingBridgeConflictValue(
                type: .string,
                encodedValue: localName
              ),
              sharedValue: HerdSharingBridgeConflictValue(
                type: .string,
                encodedValue: sharedName
              )
            )
          ]
        )
      ],
      preventedDeleteConflicts: []
    )
  }

  private func temporaryJournalURL(testName: String, suffix: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("yaHerd-\(testName)-\(suffix)", isDirectory: true)
      .appendingPathComponent("journal.json")
  }

  private func uuidSort(_ lhs: UUID, _ rhs: UUID) -> Bool {
    lhs.uuidString < rhs.uuidString
  }
}
