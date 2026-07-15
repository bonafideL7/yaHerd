//
//  HerdSharingRepositoryTests.swift
//  yaHerdTests
//

import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingRepositoryTests: XCTestCase {
  func testReadinessRequiresShareRoot() throws {
    let repository = try makeRepository()

    let readiness = repository.fetchSharingReadiness(
      for: nil,
      storageMode: .iCloud
    )

    XCTAssertEqual(readiness.state, .shareRootMissing)
    XCTAssertFalse(readiness.shareActionEnabled)
  }

  func testReadinessRequiresICloudStorage() throws {
    let repository = try makeRepository()
    let herd = makeHerdSummary()

    let readiness = repository.fetchSharingReadiness(
      for: herd,
      storageMode: .localOnly
    )

    XCTAssertEqual(readiness.state, .iCloudSyncRequired)
    XCTAssertFalse(readiness.shareActionEnabled)
  }

  func testICloudReadinessEnablesSharingBridge() throws {
    let repository = try makeRepository()
    let herd = makeHerdSummary()

    let readiness = repository.fetchSharingReadiness(
      for: herd,
      storageMode: .iCloud
    )

    XCTAssertEqual(readiness.state, .sharingAdapterAvailable)
    XCTAssertTrue(readiness.shareActionEnabled)
  }

  func testStartSharingRequiresICloudStorageBeforeLoadingCoreData() async throws {
    let repository = try makeRepository()
    let herd = makeHerdSummary()

    do {
      _ = try await repository.startSharing(
        herd: herd,
        storageMode: .localOnly
      )
      XCTFail("Expected iCloud Sync requirement error.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .iCloudSyncRequired)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testAcceptInvitationUseCaseRequiresPendingInvitation() async {
    let repository = MissingInvitationTestHerdSharingRepository()

    do {
      _ = try await AcceptHerdShareInvitationUseCase(repository: repository).execute(
        invitation: nil,
        storageMode: .iCloud
      )
      XCTFail("Expected missing share invitation error.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .shareInvitationMissing)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testSyncUseCaseRequiresHerd() async {
    let repository = MissingInvitationTestHerdSharingRepository()

    do {
      _ = try await SyncSharedHerdDataUseCase(repository: repository).execute(
        herd: nil,
        storageMode: .iCloud
      )
      XCTFail("Expected missing share root error.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .shareRootMissing)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testSyncRequiresICloudStorageBeforeLoadingCoreData() async throws {
    let repository = try makeRepository()
    let herd = makeHerdSummary()

    do {
      _ = try await repository.syncSharedBridgeData(
        herd: herd,
        storageMode: .localOnly
      )
      XCTFail("Expected iCloud Sync requirement error.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(error, .iCloudSyncRequired)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testWritableParticipantImportsCollaboratorChangesBeforeMirroringLocalData() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herdID = UUID()
    let localHerd = Herd(
      publicID: herdID,
      name: "Stale local herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(localHerd)
    try context.save()

    let syncStore = RecordingHerdSharingBridgeSyncStore(herdID: herdID)
    let repository = CoreDataHerdSharingRepository(
      context: context,
      syncStore: syncStore
    )

    let result = try await repository.syncSharedBridgeData(
      herd: localHerd.toSummary(),
      storageMode: .iCloud
    )

    XCTAssertEqual(syncStore.operationOrder, ["access", "import", "export"])
    XCTAssertEqual(syncStore.exportedHerd?.name, "Downloaded collaborator herd")
    XCTAssertEqual(syncStore.exportedHerd?.updatedAt, Date(timeIntervalSince1970: 10))
    XCTAssertTrue(result.message.hasPrefix("Imported"))
  }

  func testOwnerImportsPrivateBridgeChangesBeforeMirroringLocalData() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herdID = UUID()
    let localHerd = Herd(
      publicID: herdID,
      name: "Stale owner herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(localHerd)
    try context.save()

    let ownerAccess = HerdSharingAccess.ownerPrivateStore(participantCount: 2)
    let syncStore = RecordingHerdSharingBridgeSyncStore(
      herdID: herdID,
      access: ownerAccess
    )
    let repository = CoreDataHerdSharingRepository(
      context: context,
      syncStore: syncStore
    )

    let result = try await repository.syncSharedBridgeData(
      herd: localHerd.toSummary(),
      storageMode: .iCloud
    )

    XCTAssertEqual(syncStore.operationOrder, ["access", "import", "export"])
    XCTAssertEqual(syncStore.importedAccess, ownerAccess)
    XCTAssertEqual(syncStore.importedHerd?.publicID, herdID)
    XCTAssertEqual(syncStore.exportedHerd?.name, "Downloaded collaborator herd")
    XCTAssertEqual(syncStore.exportedHerd?.updatedAt, Date(timeIntervalSince1970: 10))
    XCTAssertTrue(result.message.hasPrefix("Imported"))
  }

  func testManualOwnerImportPassesPrivateBridgeAccessToStore() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herdID = UUID()
    let localHerd = Herd(
      publicID: herdID,
      name: "Stale owner herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(localHerd)
    try context.save()

    let ownerAccess = HerdSharingAccess.ownerPrivateStore(participantCount: 2)
    let syncStore = RecordingHerdSharingBridgeSyncStore(
      herdID: herdID,
      access: ownerAccess
    )
    let repository = CoreDataHerdSharingRepository(
      context: context,
      syncStore: syncStore
    )

    _ = try await repository.importSharedBridgeData(
      herd: localHerd.toSummary(),
      storageMode: .iCloud
    )

    XCTAssertEqual(syncStore.operationOrder, ["access", "import"])
    XCTAssertEqual(syncStore.importedAccess, ownerAccess)
    XCTAssertEqual(syncStore.importedHerd?.publicID, herdID)
    XCTAssertNil(syncStore.exportedHerd)
  }

  func testOwnerDoesNotMirrorStaleLocalDataWhenPrivateBridgeImportFails() async throws {
    let container = try TestSupport.makeModelContainer()
    let context = container.mainContext
    let herdID = UUID()
    let localHerd = Herd(
      publicID: herdID,
      name: "Stale local herd",
      createdAt: Date(timeIntervalSince1970: 1),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    context.insert(localHerd)
    try context.save()

    let syncStore = RecordingHerdSharingBridgeSyncStore(
      herdID: herdID,
      access: .ownerPrivateStore(participantCount: 2),
      importError: .bridgeImportFailed("Shared records could not be merged safely.")
    )
    let repository = CoreDataHerdSharingRepository(
      context: context,
      syncStore: syncStore
    )

    do {
      _ = try await repository.syncSharedBridgeData(
        herd: localHerd.toSummary(),
        storageMode: .iCloud
      )
      XCTFail("Expected the failed shared import to stop the writable sync.")
    } catch let error as HerdSharingActionError {
      XCTAssertEqual(
        error,
        .bridgeImportFailed("Shared records could not be merged safely.")
      )
    }

    XCTAssertEqual(syncStore.operationOrder, ["access", "import"])
    XCTAssertNil(syncStore.exportedHerd)
  }

  private func makeRepository() throws -> CoreDataHerdSharingRepository {
    let container = try TestSupport.makeModelContainer()
    return CoreDataHerdSharingRepository(context: container.mainContext)
  }

  private func makeHerdSummary() -> HerdSummary {
    HerdSummary(
      publicID: UUID(),
      name: "Test Herd",
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 1),
      schemaVersion: 1
    )
  }
}

@MainActor
private final class RecordingHerdSharingBridgeSyncStore: HerdSharingBridgeSyncStore {
  let herdID: UUID
  let access: HerdSharingAccess
  let importError: HerdSharingActionError?
  private(set) var operationOrder: [String] = []
  private(set) var importedHerd: HerdSummary?
  private(set) var importedAccess: HerdSharingAccess?
  private(set) var exportedHerd: HerdSummary?

  init(
    herdID: UUID,
    access: HerdSharingAccess = .acceptedSharedStore(
      permission: .readWrite,
      participantCount: 2
    ),
    importError: HerdSharingActionError? = nil
  ) {
    self.herdID = herdID
    self.access = access
    self.importError = importError
  }

  func fetchSharingAccess(for herd: HerdSummary) async throws -> HerdSharingAccess {
    operationOrder.append("access")
    return access
  }

  func importBridgeRecordsIntoSwiftData(
    for herd: HerdSummary,
    access: HerdSharingAccess,
    context: ModelContext
  ) async throws -> HerdSharingBridgeImportResult {
    operationOrder.append("import")
    importedHerd = herd
    importedAccess = access
    if let importError {
      throw importError
    }

    let herd = try XCTUnwrap(
      context.fetch(FetchDescriptor<Herd>()).first { candidate in
        candidate.publicID == herdID
      }
    )
    herd.name = "Downloaded collaborator herd"
    herd.updatedAt = Date(timeIntervalSince1970: 10)
    try context.save()

    return HerdSharingBridgeImportResult(
      herdName: herd.name,
      insertedTagColorDefinitionCount: 0,
      updatedTagColorDefinitionCount: 0,
      insertedStatusReferenceCount: 0,
      updatedStatusReferenceCount: 0,
      insertedAnimalTagCount: 0,
      updatedAnimalTagCount: 0,
      insertedPastureGroupCount: 0,
      updatedPastureGroupCount: 0,
      insertedPastureCount: 0,
      updatedPastureCount: 0,
      insertedAnimalCount: 0,
      updatedAnimalCount: 0,
      insertedMovementCount: 0,
      updatedMovementCount: 0,
      insertedStatusRecordCount: 0,
      updatedStatusRecordCount: 0,
      insertedHealthRecordCount: 0,
      updatedHealthRecordCount: 0,
      insertedPregnancyCheckCount: 0,
      updatedPregnancyCheckCount: 0,
      insertedWorkingProtocolTemplateCount: 0,
      updatedWorkingProtocolTemplateCount: 0,
      insertedWorkingSessionCount: 0,
      updatedWorkingSessionCount: 0,
      insertedWorkingQueueItemCount: 0,
      updatedWorkingQueueItemCount: 0,
      insertedWorkingTreatmentRecordCount: 0,
      updatedWorkingTreatmentRecordCount: 0,
      insertedFieldCheckSessionCount: 0,
      updatedFieldCheckSessionCount: 0,
      insertedFieldCheckAnimalCheckCount: 0,
      updatedFieldCheckAnimalCheckCount: 0,
      insertedFieldCheckFindingCount: 0,
      updatedFieldCheckFindingCount: 0,
      deletedRecordCount: 0,
      conflictReport: .empty
    )
  }

  func syncBridgeRecordsFromSwiftData(
    herd: HerdSummary,
    tagColorDefinitions _: [TagColorDefinition],
    statusReferences _: [AnimalStatusReference],
    animalTags _: [AnimalTag],
    pastureGroups _: [PastureGroup],
    pastures _: [Pasture],
    animals _: [Animal],
    movements _: [MovementRecord],
    statusRecords _: [StatusRecord],
    healthRecords _: [HealthRecord],
    pregnancyChecks _: [PregnancyCheck],
    workingProtocolTemplates _: [WorkingProtocolTemplate],
    workingSessions _: [WorkingSession],
    workingQueueItems _: [WorkingQueueItem],
    workingTreatmentRecords _: [WorkingTreatmentRecord],
    fieldCheckSessions _: [FieldCheckSession],
    fieldCheckAnimalChecks _: [FieldCheckAnimalCheck],
    fieldCheckFindings _: [FieldCheckFinding]
  ) async throws -> HerdSharingBridgeExportResult {
    operationOrder.append("export")
    exportedHerd = herd
    return HerdSharingBridgeExportResult(
      herdName: herd.name,
      writeTargetDescription: "accepted shared store",
      didUpdateExistingCloudKitShare: false,
      exportedTagColorDefinitionCount: 0,
      exportedStatusReferenceCount: 0,
      exportedAnimalTagCount: 0,
      exportedPastureGroupCount: 0,
      exportedPastureCount: 0,
      exportedAnimalCount: 0,
      exportedMovementCount: 0,
      exportedStatusRecordCount: 0,
      exportedHealthRecordCount: 0,
      exportedPregnancyCheckCount: 0,
      exportedWorkingProtocolTemplateCount: 0,
      exportedWorkingSessionCount: 0,
      exportedWorkingQueueItemCount: 0,
      exportedWorkingTreatmentRecordCount: 0,
      exportedFieldCheckSessionCount: 0,
      exportedFieldCheckAnimalCheckCount: 0,
      exportedFieldCheckFindingCount: 0,
      exportedDeletedRecordCount: 0
    )
  }
}

@MainActor
private final class MissingInvitationTestHerdSharingRepository: HerdSharingRepository {
  func fetchSharingReadiness(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) -> HerdSharingReadiness {
    .sharingAdapterAvailable
  }

  func fetchSharingAccess(
    for herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingAccess {
    .localOwnerBridgePending
  }

  func startSharing(
    herd: HerdSummary,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func acceptShareInvitation(
    _ invitation: HerdShareInvitation,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    XCTFail("Repository should not be called when the invitation is missing.")
    return HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func importSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func acceptPreventedSharedDeletes(
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    XCTFail("Repository should not be called when the invitation is missing.")
    return HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    in review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    XCTFail("Repository should not be called when no local fields are selected.")
    return HerdSharingActionResult(title: "Unused", message: "Unused")
  }

  func syncSharedBridgeData(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    XCTFail("Repository should not be called when the herd is missing.")
    return HerdSharingActionResult(title: "Unused", message: "Unused")
  }
}
