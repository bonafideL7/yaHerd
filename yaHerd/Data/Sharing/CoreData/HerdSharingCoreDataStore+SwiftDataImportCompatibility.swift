//
//  HerdSharingCoreDataStore+SwiftDataImportCompatibility.swift
//  yaHerd
//

import SwiftData

extension HerdSharingCoreDataStore {
  func upsertSwiftDataWorkingSessions(
    from sharedRecords: [SharedWorkingSessionRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    try HerdSharingSwiftDataImportEngine.upsertSwiftDataWorkingSessions(
      from: sharedRecords,
      herd: herd,
      in: context
    )
  }

  func upsertSwiftDataWorkingQueueItems(
    from sharedRecords: [SharedWorkingQueueItemRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    try HerdSharingSwiftDataImportEngine.upsertSwiftDataWorkingQueueItems(
      from: sharedRecords,
      herd: herd,
      in: context
    )
  }

  func upsertSwiftDataWorkingTreatmentRecords(
    from sharedRecords: [SharedWorkingTreatmentRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (
    inserted: Int, updated: Int, updatedRecordConflicts: [HerdSharingBridgeConflictDetail]
  ) {
    try HerdSharingSwiftDataImportEngine.upsertSwiftDataWorkingTreatmentRecords(
      from: sharedRecords,
      herd: herd,
      in: context
    )
  }
}
