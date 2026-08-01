//
//  HerdSharingCoreDataStore+SwiftDataMutations.swift
//  yaHerd
//

import Foundation
import SwiftData

extension HerdSharingCoreDataStore {
  func acceptPreventedSharedDeletes(
    _ conflicts: [HerdSharingPreventedDeleteConflict],
    context: ModelContext
  ) throws -> Int {
    try HerdSharingSwiftDataMutationEngine.acceptPreventedSharedDeletes(
      conflicts,
      context: context
    )
  }

  func restoreLocalFields(
    _ selections: [HerdSharingLocalFieldRestoreSelection],
    from review: HerdSharingConflictReview,
    context: ModelContext
  ) throws -> HerdSharingLocalFieldRestoreResult {
    try HerdSharingSwiftDataMutationEngine.restoreLocalFields(
      selections,
      from: review,
      context: context
    )
  }

  func deleteSwiftDataRecords(
    from tombstones: [SharedDeletedRecord],
    herd: Herd,
    in context: ModelContext
  ) throws -> (deletedCount: Int, preventedDeleteConflicts: [HerdSharingBridgeConflictDetail]) {
    try HerdSharingSwiftDataMutationEngine.deleteSwiftDataRecords(
      from: tombstones,
      herd: herd,
      in: context
    )
  }

  func fetchSwiftDataRecord<T: PersistentModel>(
    _ type: T.Type,
    publicID: UUID,
    keyPath: KeyPath<T, UUID>,
    in context: ModelContext
  ) throws -> T? {
    try HerdSharingSwiftDataMutationEngine.fetchSwiftDataRecord(
      type,
      publicID: publicID,
      keyPath: keyPath,
      in: context
    )
  }
}
