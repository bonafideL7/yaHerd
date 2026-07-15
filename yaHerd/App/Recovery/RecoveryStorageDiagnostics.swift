//
//  RecoveryStorageDiagnostics.swift
//  yaHerd
//

import Foundation

struct RecoveryStoreFileDiagnostic: Identifiable, Equatable {
  let archiveName: String
  let originalFilename: String
  let byteCount: Int
  let modifiedAt: Date

  var id: String { archiveName }
}

struct RecoveryStorageDiagnostics: Equatable {
  let generatedAt: Date
  let recoveryStoreCounts: SyncDiagnosticsCounts
  let recoveryStoreCountError: String?
  let recoverableStoreFiles: [RecoveryStoreFileDiagnostic]

  static let empty = RecoveryStorageDiagnostics(
    generatedAt: .distantPast,
    recoveryStoreCounts: .empty,
    recoveryStoreCountError: nil,
    recoverableStoreFiles: []
  )

  var totalRecoveryRecordCount: Int {
    let counts = recoveryStoreCounts
    return counts.herds
      + counts.animals
      + counts.pastures
      + counts.pastureGroups
      + counts.healthRecords
      + counts.pregnancyChecks
      + counts.movementRecords
      + counts.statusRecords
      + counts.workingSessions
      + counts.workingQueueItems
      + counts.workingTreatmentRecords
      + counts.fieldCheckSessions
      + counts.fieldCheckAnimalChecks
      + counts.fieldCheckFindings
  }

  var recoverableStoreByteCount: Int {
    recoverableStoreFiles.reduce(0) { $0 + $1.byteCount }
  }
}
