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
  let recoverableStoreFiles: [RecoveryStoreFileDiagnostic]

  static let empty = RecoveryStorageDiagnostics(
    generatedAt: .distantPast,
    recoverableStoreFiles: []
  )

  var recoverableStoreByteCount: Int {
    recoverableStoreFiles.reduce(0) { $0 + $1.byteCount }
  }
}
