import Foundation
import SwiftData

protocol HerdSharingTransactionalImportApplying: Sendable {
  func prepareImport(
    _ snapshot: HerdSharingBridgeStoreSnapshot,
    pendingConflictReport: HerdSharingBridgeConflictReport?,
    failureInjector: HerdSharingBridgeFailureInjector
  ) async throws -> HerdSharingSwiftDataImportApplication

  func commitImport(
    _ preparation: HerdSharingSwiftDataImportApplication,
    snapshot: HerdSharingBridgeStoreSnapshot,
    failureInjector: HerdSharingBridgeFailureInjector
  ) async throws -> HerdSharingSwiftDataImportApplication

  func rollbackPreparedImport() async
}

extension SwiftDataHerdSharingActor: HerdSharingTransactionalImportApplying {
  func prepareImport(
    _ snapshot: HerdSharingBridgeStoreSnapshot,
    pendingConflictReport: HerdSharingBridgeConflictReport?,
    failureInjector: HerdSharingBridgeFailureInjector
  ) throws -> HerdSharingSwiftDataImportApplication {
    try PerformanceLog.measure("SwiftData.sharing.prepareImport") {
      try HerdSharingSwiftDataImportEngine.prepare(
        snapshot,
        pendingConflictReport: pendingConflictReport,
        failureInjector: failureInjector,
        in: modelContext
      )
    }
  }

  func commitImport(
    _ preparation: HerdSharingSwiftDataImportApplication,
    snapshot: HerdSharingBridgeStoreSnapshot,
    failureInjector: HerdSharingBridgeFailureInjector
  ) throws -> HerdSharingSwiftDataImportApplication {
    try PerformanceLog.measure("SwiftData.sharing.commitImport") {
      try HerdSharingSwiftDataImportEngine.commit(
        preparation,
        snapshot: snapshot,
        failureInjector: failureInjector,
        in: modelContext
      )
    }
  }

  func rollbackPreparedImport() {
    modelContext.rollback()
  }
}

extension HerdSharingSwiftDataImportEngine {
  static func apply(
    _ snapshot: HerdSharingBridgeStoreSnapshot,
    pendingConflictReport: HerdSharingBridgeConflictReport?,
    failureInjector: HerdSharingBridgeFailureInjector,
    in context: ModelContext
  ) throws -> HerdSharingSwiftDataImportApplication {
    let preparation = try prepare(
      snapshot,
      pendingConflictReport: pendingConflictReport,
      failureInjector: failureInjector,
      in: context
    )
    return try commit(
      preparation,
      snapshot: snapshot,
      failureInjector: failureInjector,
      in: context
    )
  }
}
