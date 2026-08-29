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
              localValue: HerdSharingBridgeConflictValue(type: .string, encodedValue: localName),
              sharedValue: HerdSharingBridgeConflictValue(type: .string, encodedValue: sharedName)
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

@MainActor
extension HerdSharingBridgeReliabilityTests {
  func testAmbiguousInvitationAcceptanceRetainsPendingScopeAndRequiresVerification() async throws {
    let suiteName = "BridgeReliabilityAmbiguousAcceptance.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      currentAccountRecordNameProvider: { "account-A" }
    )
    let scope = bridgeReliabilityAcceptedScope()
    let store = HerdSharingCoreDataStore(acceptedShareImportScopeStore: scopeStore)

    do {
      try await store.commitAcceptedShareInvitationScope(scope) {
        throw AmbiguousInvitationAcceptanceTestError.responseInterrupted
      }
      XCTFail("Expected ambiguous acceptance to require access verification.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeImportRequiresAccessVerification(let message) = error else {
        XCTFail("Expected bridgeImportRequiresAccessVerification, received \(error).")
        return
      }
      XCTAssertTrue(message.contains("exact invitation scope was retained"))
      XCTAssertTrue(message.contains("may already have committed"))
    }

    XCTAssertEqual(try scopeStore.pendingScopes(), [scope])
    XCTAssertEqual(scopeStore.immediateImportScope, scope)
  }

  func testSuccessfulInvitationAcceptanceMarksRetainedScopeAccepted() async throws {
    let suiteName = "BridgeReliabilitySuccessfulAcceptance.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
      XCTFail("Could not create isolated UserDefaults suite.")
      return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let scopeStore = HerdSharingAcceptedShareImportScopeStore(
      defaults: defaults,
      storageKey: "pending-scopes",
      currentAccountRecordNameProvider: { "account-A" }
    )
    let scope = bridgeReliabilityAcceptedScope()
    let store = HerdSharingCoreDataStore(acceptedShareImportScopeStore: scopeStore)

    try await store.commitAcceptedShareInvitationScope(scope) {}

    let persisted = try XCTUnwrap(try scopeStore.pendingScopes().first)
    XCTAssertEqual(persisted.acceptanceState, .accepted)
    XCTAssertEqual(persisted.rootRecordID, scope.rootRecordID)
    XCTAssertEqual(persisted.participantAccountRecordName, "account-A")
    XCTAssertEqual(scopeStore.immediateImportScope, persisted)
  }

  func testCorruptBridgeJournalBacksUpEvidenceAndSchedulesImportFirstRecovery() async throws {
    let directory = bridgeRecoveryDirectory("CorruptJournal")
    let journalURL = directory.appendingPathComponent("HerdSharingSyncJournal.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let corruptData = Data("not-valid-json".utf8)
    try corruptData.write(to: journalURL)
    let herdID = UUID()
    let journal = HerdSharingBridgeJournal(fileURL: journalURL)
    let unfinished = await journal.unfinishedOperations(for: herdID)

    XCTAssertEqual(unfinished.count, 1)
    XCTAssertEqual(unfinished.first?.herdPublicID, herdID)
    XCTAssertEqual(unfinished.first?.direction, .importFromBridge)
    XCTAssertEqual(unfinished.first?.state, .failed)
    XCTAssertEqual(unfinished.first?.bridgeLocation, "corrupt persisted bridge journal")

    do {
      _ = try await journal.begin(
        herdPublicID: herdID,
        direction: .exportToBridge,
        bridgeLocation: HerdSharingAccess.BridgeLocation.ownerPrivateStore.journalDescription
      )
      XCTFail("Expected corrupt journal state to reject a new operation before recovery.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed = error else {
        XCTFail("Expected bridgeConsistencyFailed, received \(error).")
        return
      }
    }
    XCTAssertEqual(try Data(contentsOf: journalURL), corruptData)

    let container = try TestSupport.makeModelContainer()
    let guardService = HerdSharingCreationStateGuard(
      context: container.mainContext,
      journal: journal,
      ownershipRegistry: BridgeRecoveryOwnershipRegistry(),
      accountOwnershipRegistry: BridgeRecoveryAccountOwnershipRegistry()
    )
    let herd = HerdSummary(
      publicID: herdID,
      name: "Corrupt Journal Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2),
      schemaVersion: 1
    )
    let participantAccess = HerdSharingAccess.acceptedSharedStore(
      permission: .readWrite,
      participantCount: 2
    )

    let evaluatedAccess = try await guardService.evaluate(herd: herd, access: participantAccess)
    XCTAssertEqual(evaluatedAccess.creationState, .pendingBridgeOperation)
    let disposition = try await guardService.synchronizationDisposition(
      herd: herd,
      access: participantAccess
    )
    XCTAssertEqual(disposition, .fullSync)

    let recoveryOperations = await journal.unfinishedOperations(for: herdID)
    let recovery = try XCTUnwrap(recoveryOperations.first)
    XCTAssertFalse(HerdSharingBridgeJournal.isCorruptJournalSafetyOperation(recovery))
    XCTAssertEqual(recovery.direction, .importFromBridge)
    XCTAssertEqual(
      recovery.bridgeLocation,
      HerdSharingAccess.BridgeLocation.acceptedSharedStore.journalDescription
    )
    XCTAssertTrue(recovery.lastErrorDescription?.contains("import-first recovery") == true)

    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    let backups = files.filter { $0.lastPathComponent.contains(".corrupt-backup-") }
    XCTAssertEqual(backups.count, 1)
    XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(backups.first)), corruptData)
    XCTAssertNotEqual(try Data(contentsOf: journalURL), corruptData)
  }

  func testCorruptBridgeJournalRecoveryPlanSurvivesJournalReload() async throws {
    let directory = bridgeRecoveryDirectory("CorruptJournalReload")
    let journalURL = directory.appendingPathComponent("HerdSharingSyncJournal.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let corruptData = Data("not-valid-json".utf8)
    try corruptData.write(to: journalURL)

    let herdID = UUID()
    let bridgeLocation = HerdSharingAccess.BridgeLocation.acceptedSharedStore.journalDescription
    let now = Date(timeIntervalSince1970: 500)
    let journal = HerdSharingBridgeJournal(fileURL: journalURL)
    let backupURL = try await journal.backupAndResetCorruptJournal(
      recoveryPlan: HerdSharingCorruptJournalRecoveryPlan(
        herdPublicID: herdID,
        bridgeLocation: bridgeLocation
      ),
      now: now
    )

    let installedOperations = await journal.unfinishedOperations(for: herdID)
    let installed = try XCTUnwrap(installedOperations.first)
    XCTAssertEqual(installedOperations.count, 1)
    XCTAssertEqual(installed.direction, .importFromBridge)
    XCTAssertEqual(installed.bridgeLocation, bridgeLocation)
    XCTAssertEqual(installed.state, .failed)
    XCTAssertEqual(installed.createdAt, now)
    XCTAssertTrue(installed.lastErrorDescription?.contains(backupURL.lastPathComponent) == true)
    XCTAssertEqual(try Data(contentsOf: backupURL), corruptData)

    let reloadedOperations = await HerdSharingBridgeJournal(fileURL: journalURL)
      .unfinishedOperations(for: herdID)
    XCTAssertEqual(reloadedOperations, installedOperations)
  }

  func testCorruptBridgeJournalRecoveryLeavesActiveBytesUntouchedWhenBackupFails() async throws {
    let directory = bridgeRecoveryDirectory("CorruptJournalBackupFailure")
    let journalURL = directory.appendingPathComponent("HerdSharingSyncJournal.json")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let corruptData = Data("not-valid-json".utf8)
    try corruptData.write(to: journalURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      try? FileManager.default.removeItem(at: directory)
    }

    let herdID = UUID()
    let journal = HerdSharingBridgeJournal(fileURL: journalURL)
    do {
      _ = try await journal.backupAndResetCorruptJournal()
      XCTFail("Expected journal recovery to fail when corrupt evidence cannot be backed up.")
    } catch let error as HerdSharingActionError {
      guard case .bridgeConsistencyFailed(let message) = error else {
        XCTFail("Expected bridgeConsistencyFailed, received \(error).")
        return
      }
      XCTAssertTrue(message.contains("could not be backed up"))
    }

    XCTAssertEqual(try Data(contentsOf: journalURL), corruptData)
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    XCTAssertTrue(files.filter { $0.lastPathComponent.contains(".corrupt-backup-") }.isEmpty)
    let unfinishedAfterFailure = await journal.unfinishedOperations(for: herdID)
    XCTAssertTrue(
      unfinishedAfterFailure.contains(where: HerdSharingBridgeJournal.isCorruptJournalSafetyOperation)
    )
  }

  func testCorruptJournalWithMissingBridgeRevokesCachedLocalOwnerAuthority() async throws {
    let directory = bridgeRecoveryDirectory("CorruptMissingBridge")
    let journalURL = directory.appendingPathComponent("HerdSharingSyncJournal.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not-valid-json".utf8).write(to: journalURL)

    let herdID = UUID()
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herdModel = Herd(
      publicID: herdID,
      name: "Missing Bridge Herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(herdModel)
    try context.save()

    let ownershipRegistry = BridgeRecoveryOwnershipRegistry()
    ownershipRegistry.recordOwner(
      herdPublicID: herdID,
      deviceID: CollaborationIdentityProvider.current().deviceID
    )
    let journal = HerdSharingBridgeJournal(fileURL: journalURL)
    let guardService = HerdSharingCreationStateGuard(
      context: context,
      journal: journal,
      ownershipRegistry: ownershipRegistry,
      accountOwnershipRegistry: BridgeRecoveryAccountOwnershipRegistry()
    )

    do {
      _ = try await guardService.synchronizationDisposition(
        herd: herdModel.toSummary(),
        access: .localOwnerBridgePending
      )
      XCTFail("Expected missing-bridge recovery to require owner verification.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .ownerBridgeVerificationRequired)
    }

    XCTAssertNil(ownershipRegistry.ownership(for: herdID))
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    XCTAssertEqual(files.filter { $0.lastPathComponent.contains(".corrupt-backup-") }.count, 1)
  }
}

private enum AmbiguousInvitationAcceptanceTestError: LocalizedError {
  case responseInterrupted

  var errorDescription: String? {
    "The CloudKit acceptance response was interrupted."
  }
}

private func bridgeReliabilityAcceptedScope() -> HerdSharingAcceptedShareImportScope {
  HerdSharingAcceptedShareImportScope(
    shareIdentifier: "ambiguous-share",
    rootRecordName: "ambiguous-root",
    rootZoneName: "ambiguous-zone",
    rootZoneOwnerName: "ambiguous-owner",
    acceptedAt: Date(timeIntervalSince1970: 10),
    participantAccountRecordName: "account-A",
    acceptanceState: .pending
  )
}

private func bridgeRecoveryDirectory(_ name: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("HerdSharingBridgeReliabilityTests", isDirectory: true)
    .appendingPathComponent(name, isDirectory: true)
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private final class BridgeRecoveryOwnershipRegistry: HerdSharingOwnershipRecording {
  private var values: [UUID: HerdSharingOwnership] = [:]

  func ownership(for herdPublicID: UUID) -> HerdSharingOwnership? { values[herdPublicID] }
  func recordOwner(herdPublicID: UUID, deviceID: String) {
    values[herdPublicID] = .owner(deviceID: deviceID)
  }
  func recordParticipant(herdPublicID: UUID) { values[herdPublicID] = .participant }
  func recordDetachedParticipant(herdPublicID: UUID) {
    values[herdPublicID] = .detachedParticipant
  }
  func clearOwnership(for herdPublicID: UUID) { values.removeValue(forKey: herdPublicID) }
}

private final class BridgeRecoveryAccountOwnershipRegistry: HerdSharingAccountOwnershipRecording {
  private var establishedOwnerShares: Set<UUID> = []

  func hasEstablishedOwnerShare(for herdPublicID: UUID) -> Bool {
    establishedOwnerShares.contains(herdPublicID)
  }
  func recordEstablishedOwnerShare(for herdPublicID: UUID) {
    establishedOwnerShares.insert(herdPublicID)
  }
  func clearEstablishedOwnerShare(for herdPublicID: UUID) {
    establishedOwnerShares.remove(herdPublicID)
  }
}