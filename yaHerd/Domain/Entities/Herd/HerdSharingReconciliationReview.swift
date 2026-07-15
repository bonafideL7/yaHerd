//
//  HerdSharingReconciliationReview.swift
//  yaHerd
//

import Foundation

struct HerdSharingReconciliationReview: Equatable, Identifiable {
  let id: UUID
  let detectedAt: Date
  let entities: [HerdSharingEntityReconciliation]
  let deletionTombstoneCount: Int

  init(
    id: UUID = UUID(),
    detectedAt: Date = .now,
    entities: [HerdSharingEntityReconciliation],
    deletionTombstoneCount: Int
  ) {
    self.id = id
    self.detectedAt = detectedAt
    self.entities = entities
    self.deletionTombstoneCount = deletionTombstoneCount
  }

  var unresolvedDifferenceCount: Int {
    entities.reduce(0) { $0 + $1.unresolvedDifferenceCount }
  }

  var duplicatePublicIDCount: Int {
    entities.reduce(0) { $0 + $1.duplicatePublicIDCount }
  }

  var hasUnresolvedDifferences: Bool {
    unresolvedDifferenceCount > 0
  }

  var unresolvedEntities: [HerdSharingEntityReconciliation] {
    entities.filter(\.hasUnresolvedDifferences)
  }

  var summary: String {
    guard hasUnresolvedDifferences else {
      return
        "Reconciliation is clean across \(entities.count) entity types. \(deletionTombstoneCount) deletion tombstone(s) remain in the bridge."
    }

    return
      "Found \(unresolvedDifferenceCount) unresolved difference(s), including \(duplicatePublicIDCount) duplicate public ID(s), across \(unresolvedEntities.count) entity type(s)."
  }
}

struct HerdSharingEntityReconciliation: Equatable, Identifiable {
  let entityName: String
  let localRecordCount: Int
  let bridgeRecordCount: Int
  let missingInBridge: [UUID]
  let missingInSwiftData: [UUID]
  let duplicateLocalPublicIDs: [UUID]
  let duplicateBridgePublicIDs: [UUID]

  var id: String { entityName }

  var unresolvedDifferenceCount: Int {
    missingInBridge.count
      + missingInSwiftData.count
      + duplicateLocalPublicIDs.count
      + duplicateBridgePublicIDs.count
  }

  var duplicatePublicIDCount: Int {
    duplicateLocalPublicIDs.count + duplicateBridgePublicIDs.count
  }

  var hasUnresolvedDifferences: Bool {
    unresolvedDifferenceCount > 0
  }
}
