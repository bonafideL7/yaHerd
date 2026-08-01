//
//  HerdSharingSwiftDataImportEngine+DeletionCanonicalization.swift
//  yaHerd
//

import Foundation

extension HerdSharingSwiftDataImportEngine {
  private struct DeletionRecordKey: Hashable {
    let sourceEntityName: String
    let publicID: UUID
  }

  /// Deletion tombstones use a composite identity. Different entity types may
  /// legitimately reuse the same application-managed UUID and must not replace
  /// one another during import canonicalization.
  static func canonicalImportRecords(
    _ records: [SharedDeletedRecord]
  ) -> [SharedDeletedRecord] {
    var canonicalByIdentity: [DeletionRecordKey: SharedDeletedRecord] = [:]
    var recordsWithoutIdentity: [SharedDeletedRecord] = []

    for record in records {
      guard let publicID = record.parsedPublicID,
        let sourceEntityName = record.sourceEntityName,
        !sourceEntityName.isEmpty
      else {
        recordsWithoutIdentity.append(record)
        continue
      }

      let key = DeletionRecordKey(
        sourceEntityName: sourceEntityName,
        publicID: publicID
      )
      guard let existing = canonicalByIdentity[key] else {
        canonicalByIdentity[key] = record
        continue
      }

      if deletionRecordSort(record, existing) {
        canonicalByIdentity[key] = record
      }
    }

    return recordsWithoutIdentity + canonicalByIdentity.values
  }

  private static func deletionRecordSort(
    _ lhs: SharedDeletedRecord,
    _ rhs: SharedDeletedRecord
  ) -> Bool {
    let lhsDate = lhs.lastMirroredAt ?? .distantPast
    let rhsDate = rhs.lastMirroredAt ?? .distantPast
    if lhsDate != rhsDate { return lhsDate > rhsDate }

    let lhsDeletedAt = lhs.deletedAt ?? .distantPast
    let rhsDeletedAt = rhs.deletedAt ?? .distantPast
    return lhsDeletedAt > rhsDeletedAt
  }
}
