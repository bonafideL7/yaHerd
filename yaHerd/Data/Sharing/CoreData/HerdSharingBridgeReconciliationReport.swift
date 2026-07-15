//
//  HerdSharingBridgeReconciliationReport.swift
//  yaHerd
//

import Foundation

struct HerdSharingBridgeEntityReconciliation: Codable, Equatable {
  let step: HerdSharingBridgeStep
  let localRecordCount: Int
  let bridgeRecordCount: Int
  let missingInBridge: [UUID]
  let missingInSwiftData: [UUID]
  let duplicateLocalPublicIDs: [UUID]
  let duplicateBridgePublicIDs: [UUID]

  var unresolvedDifferenceCount: Int {
    missingInBridge.count
      + missingInSwiftData.count
      + duplicateLocalPublicIDs.count
      + duplicateBridgePublicIDs.count
  }
}

struct HerdSharingBridgeReconciliationReport: Codable, Equatable {
  static let empty = HerdSharingBridgeReconciliationReport(
    entities: [],
    deletionTombstoneCount: 0
  )

  let entities: [HerdSharingBridgeEntityReconciliation]
  let deletionTombstoneCount: Int

  var unresolvedDifferenceCount: Int {
    entities.reduce(0) { $0 + $1.unresolvedDifferenceCount }
  }

  var duplicatePublicIDCount: Int {
    entities.reduce(0) {
      $0 + $1.duplicateLocalPublicIDs.count + $1.duplicateBridgePublicIDs.count
    }
  }

  var hasUnresolvedDifferences: Bool {
    unresolvedDifferenceCount > 0
  }

  var summary: String {
    guard hasUnresolvedDifferences else {
      return
        "Reconciliation clean across \(entities.count) entity types; \(deletionTombstoneCount) deletion tombstone(s) present."
    }

    let entityDetails =
      entities
      .filter { $0.unresolvedDifferenceCount > 0 }
      .map { entity in
        "\(entity.step.displayName): local-only \(entity.missingInBridge.count), bridge-only \(entity.missingInSwiftData.count), local duplicates \(entity.duplicateLocalPublicIDs.count), bridge duplicates \(entity.duplicateBridgePublicIDs.count)"
      }
      .joined(separator: "; ")
    return
      "Reconciliation found \(unresolvedDifferenceCount) unresolved difference(s), including \(duplicatePublicIDCount) duplicate public ID(s), across \(entities.count) entity types; \(deletionTombstoneCount) deletion tombstone(s) present. \(entityDetails)"
  }
}

enum HerdSharingBridgeReconciler {
  static func duplicatePublicIDs(
    in publicIDs: [HerdSharingBridgeStep: [UUID]]
  ) -> [HerdSharingBridgeStep: [UUID]] {
    publicIDs.reduce(into: [:]) { result, entry in
      let duplicates = frequencies(entry.value).compactMap { key, value in
        value > 1 ? key : nil
      }.sorted(by: uuidSort)
      if !duplicates.isEmpty {
        result[entry.key] = duplicates
      }
    }
  }

  static func makeReport(
    localPublicIDs: [HerdSharingBridgeStep: [UUID]],
    bridgePublicIDs: [HerdSharingBridgeStep: [UUID]],
    deletionTombstoneCount: Int
  ) -> HerdSharingBridgeReconciliationReport {
    let entities = HerdSharingBridgeStep.entitySteps
      .filter { $0 != .deletions }
      .map { step in
        compare(
          step: step,
          localPublicIDs: localPublicIDs[step, default: []],
          bridgePublicIDs: bridgePublicIDs[step, default: []]
        )
      }

    return HerdSharingBridgeReconciliationReport(
      entities: entities,
      deletionTombstoneCount: deletionTombstoneCount
    )
  }

  private static func compare(
    step: HerdSharingBridgeStep,
    localPublicIDs: [UUID],
    bridgePublicIDs: [UUID]
  ) -> HerdSharingBridgeEntityReconciliation {
    let localCounts = frequencies(localPublicIDs)
    let bridgeCounts = frequencies(bridgePublicIDs)
    let localSet = Set(localCounts.keys)
    let bridgeSet = Set(bridgeCounts.keys)

    return HerdSharingBridgeEntityReconciliation(
      step: step,
      localRecordCount: localPublicIDs.count,
      bridgeRecordCount: bridgePublicIDs.count,
      missingInBridge: Array(localSet.subtracting(bridgeSet)).sorted(by: uuidSort),
      missingInSwiftData: Array(bridgeSet.subtracting(localSet)).sorted(by: uuidSort),
      duplicateLocalPublicIDs: localCounts.compactMap { key, value in value > 1 ? key : nil }
        .sorted(by: uuidSort),
      duplicateBridgePublicIDs: bridgeCounts.compactMap { key, value in value > 1 ? key : nil }
        .sorted(by: uuidSort)
    )
  }

  private static func frequencies(_ values: [UUID]) -> [UUID: Int] {
    values.reduce(into: [:]) { result, value in
      result[value, default: 0] += 1
    }
  }

  private static func uuidSort(_ lhs: UUID, _ rhs: UUID) -> Bool {
    lhs.uuidString < rhs.uuidString
  }
}
