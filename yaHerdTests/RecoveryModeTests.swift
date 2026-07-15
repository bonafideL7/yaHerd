//
//  RecoveryModeTests.swift
//  yaHerdTests
//

import SwiftData
import XCTest

@testable import yaHerd

final class RecoveryModeTests: XCTestCase {
  func testRecoveryWritePolicyBlocksMutationBeforeSharingAccessRefresh() {
    let policy = HerdCollaborationWritePolicy(dataAccessMode: .recoveryReadOnly)
    var refreshRequestCount = 0
    policy.setAccessRefreshRequestHandler { _ in
      refreshRequestCount += 1
    }

    XCTAssertThrowsError(try policy.validateCanWrite(reason: .animal)) { error in
      XCTAssertEqual(
        error as? HerdCollaborationWritePolicyError,
        .recoveryModeReadOnly(reason: .animal)
      )
    }
    XCTAssertEqual(refreshRequestCount, 0)
    XCTAssertFalse(policy.snapshot.allowsLocalMutations)
    XCTAssertEqual(policy.snapshot.lastBlockedMutationReason, .animal)
  }

  @MainActor
  func testRecoverySharingRepositoryDisablesSharingReadiness() async {
    let repository = RecoveryModeHerdSharingRepository()
    let herd = HerdSummary(
      publicID: UUID(),
      name: "Recovery Test",
      createdAt: .now,
      updatedAt: .now,
      schemaVersion: 1
    )

    let readiness = repository.fetchSharingReadiness(for: herd, storageMode: .iCloud)

    XCTAssertEqual(readiness.state, .recoveryModeReadOnly)
    XCTAssertFalse(readiness.shareActionEnabled)

    do {
      _ = try await repository.fetchSharingAccess(for: herd, storageMode: .iCloud)
      XCTFail("Recovery mode must reject sharing access requests.")
    } catch {
      XCTAssertEqual(error as? HerdSharingActionError, .recoveryModeReadOnly)
    }
  }

  func testRecoveryTarArchiveContainsFilesAndTerminalBlocks() throws {
    let firstData = Data("diagnostics".utf8)
    let secondData = Data([0, 1, 2, 3, 4])

    let archive = try RecoveryTarArchiveBuilder.makeArchive(
      entries: [
        RecoveryArchiveEntry(path: "RecoveryDiagnostics.json", data: firstData),
        RecoveryArchiveEntry(path: "Storage/yaHerdStore.store", data: secondData),
      ]
    )

    XCTAssertEqual(
      String(decoding: archive.prefix(100).prefix(while: { $0 != 0 }), as: UTF8.self),
      "RecoveryDiagnostics.json")
    XCTAssertTrue(archive.count.isMultiple(of: 512))
    XCTAssertEqual(archive.suffix(1024), Data(repeating: 0, count: 1024))
    XCTAssertNotNil(archive.range(of: Data("Storage/yaHerdStore.store".utf8)))
    XCTAssertNotNil(archive.range(of: firstData))
    XCTAssertNotNil(archive.range(of: secondData))
  }

  func testRecoveryTarArchiveRejectsUnrepresentablePath() {
    let path = String(repeating: "a", count: 101)

    XCTAssertThrowsError(
      try RecoveryTarArchiveBuilder.makeArchive(
        entries: [RecoveryArchiveEntry(path: path, data: Data())]
      )
    ) { error in
      XCTAssertEqual(error as? RecoveryArchiveError, .pathTooLong(path))
    }
  }
  @MainActor
  func testRecoveryContainerRejectsPersistentSaves() throws {
    let container = try ModelContainerFactory.makeRecoveryContainer()
    let context = container.mainContext
    context.insert(Herd(name: "Must Not Save"))

    XCTAssertThrowsError(try context.save())
  }

  func testRecoveryDiagnosticsSummarizesRecordsAndStoreFiles() {
    let counts = SyncDiagnosticsCounts(
      herds: 1,
      animals: 20,
      pastures: 3,
      pastureGroups: 2,
      healthRecords: 4,
      pregnancyChecks: 5,
      movementRecords: 6,
      statusRecords: 7,
      workingSessions: 8,
      workingQueueItems: 9,
      workingTreatmentRecords: 10,
      fieldCheckSessions: 11,
      fieldCheckAnimalChecks: 12,
      fieldCheckFindings: 13
    )
    let diagnostics = RecoveryStorageDiagnostics(
      generatedAt: .now,
      recoveryStoreCounts: counts,
      recoveryStoreCountError: nil,
      recoverableStoreFiles: [
        RecoveryStoreFileDiagnostic(
          archiveName: "store",
          originalFilename: "yaHerdStore.store",
          byteCount: 2_048,
          modifiedAt: .now
        ),
        RecoveryStoreFileDiagnostic(
          archiveName: "wal",
          originalFilename: "yaHerdStore.store-wal",
          byteCount: 1_024,
          modifiedAt: .now
        ),
      ]
    )

    XCTAssertEqual(diagnostics.totalRecoveryRecordCount, 111)
    XCTAssertEqual(diagnostics.recoverableStoreByteCount, 3_072)
  }

}
