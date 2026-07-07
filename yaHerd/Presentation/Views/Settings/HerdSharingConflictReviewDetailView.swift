//
//  HerdSharingConflictReviewDetailView.swift
//  yaHerd
//

import SwiftUI

struct HerdSharingConflictReviewDetailView: View {
  @Environment(\.herdSharingConflictReviewStore) private var conflictReviewStore
  @Environment(\.herdSharingSyncCoordinator) private var sharingSyncCoordinator
  @State private var resolutionMessage: String?

  let review: HerdSharingConflictReview

  var body: some View {
    List {
      summarySection
      updatedRecordsSection
      skippedDeletesSection
      resolutionSection
      nextStepsSection
    }
    .navigationTitle("Conflict Report")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var summarySection: some View {
    Section("Summary") {
      LabeledContent("Source", value: review.sourceDescription)
      LabeledContent("Detected", value: formattedDate(review.detectedAt))
      LabeledContent(
        "Updated Existing Records",
        value: review.existingLocalRecordUpdateCount.formatted()
      )
      LabeledContent("Skipped Shared Deletes", value: review.preventedDeleteCount.formatted())

      if let earliestSharedDeletedAt = review.earliestSharedDeletedAt {
        LabeledContent("Oldest Shared Delete", value: formattedDate(earliestSharedDeletedAt))
      }

      if let latestLocalModifiedAt = review.latestLocalModifiedAt {
        LabeledContent("Newest Local Edit", value: formattedDate(latestLocalModifiedAt))
      }

      Text(review.summary)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var updatedRecordsSection: some View {
    Section("Updated Existing Local Records") {
      if review.updatedRecordConflicts.isEmpty, review.existingLocalRecordUpdateCount > 0 {
        Text(
          "This older report only contains an updated-record count. Run shared-data sync again to capture record IDs by entity."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } else if review.updatedRecordConflicts.isEmpty {
        ContentUnavailableView(
          "No Updated Local Records",
          systemImage: "checkmark.circle",
          description: Text(
            "This report did not include existing SwiftData records updated from shared data."
          )
        )
      } else {
        ForEach(review.updatedRecordEntitySummaries) { summary in
          DisclosureGroup("\(summary.displayEntityName) (\(summary.count))") {
            ForEach(updatedRecords(for: summary.displayEntityName)) { conflict in
              VStack(alignment: .leading, spacing: 6) {
                Text(conflict.publicID.uuidString)
                  .font(.caption.weight(.semibold))
                  .textSelection(.enabled)

                LabeledContent("Local modified", value: formattedImportDate(conflict.localModifiedAt))
                  .font(.caption2)
                LabeledContent("Shared mirrored", value: formattedImportDate(conflict.sharedModifiedAt))
                  .font(.caption2)

                Text(
                  "This existing SwiftData record was overwritten from the accepted shared bridge record during import."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
            }
          }
        }
      }
    }
  }

  private var skippedDeletesSection: some View {
    Section("Skipped Shared Deletes") {
      if review.preventedDeleteConflicts.isEmpty {
        ContentUnavailableView(
          "No Skipped Deletes",
          systemImage: "trash.slash",
          description: Text("No shared tombstones were blocked by newer local edit metadata.")
        )
      } else {
        ForEach(review.preventedDeleteEntitySummaries) { summary in
          DisclosureGroup("\(summary.displayEntityName) (\(summary.count))") {
            ForEach(conflicts(for: summary.displayEntityName)) { conflict in
              VStack(alignment: .leading, spacing: 6) {
                Text(conflict.publicID.uuidString)
                  .font(.caption.weight(.semibold))
                  .textSelection(.enabled)

                LabeledContent("Local edit", value: formattedDate(conflict.localModifiedAt))
                  .font(.caption2)
                LabeledContent("Shared delete", value: formattedDate(conflict.sharedDeletedAt))
                  .font(.caption2)

                Text(
                  "The local record was kept because its edit metadata is newer than the shared delete timestamp."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
            }
          }
        }
      }
    }
  }

  private var resolutionSection: some View {
    Section("Resolution") {
      Button {
        Task { await keepLocalRecords(syncAfterResolution: true) }
      } label: {
        Label("Keep Local Records and Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
      }
      .disabled(!review.hasConflicts || sharingSyncCoordinator?.isSyncing == true)

      Button {
        Task { await keepLocalRecords(syncAfterResolution: false) }
      } label: {
        Label("Mark Kept Locally", systemImage: "checkmark.circle")
      }
      .disabled(!review.hasConflicts)

      Button(role: .destructive) {
        Task { await acceptSharedDeletes(syncAfterResolution: true) }
      } label: {
        Label("Accept Shared Deletes and Sync", systemImage: "trash")
      }
      .disabled(
        review.preventedDeleteCount == 0 || sharingSyncCoordinator == nil
          || sharingSyncCoordinator?.isSyncing == true)

      Button(role: .destructive) {
        Task { await acceptSharedDeletes(syncAfterResolution: false) }
      } label: {
        Label("Accept Shared Deletes", systemImage: "trash.circle")
      }
      .disabled(review.preventedDeleteCount == 0 || sharingSyncCoordinator == nil)

      if let resolutionMessage {
        Text(resolutionMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(
        "Keep Local Records preserves the local records. Accept Shared Deletes deletes the affected local SwiftData records by public ID, resolves the report, and can immediately run shared-data sync so the bridge stays aligned."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var nextStepsSection: some View {
    Section("Next Steps") {
      Text(review.recommendedAction)
        .font(.caption)
        .foregroundStyle(.secondary)

      Text(
        "This screen can now resolve skipped shared deletes directly. It still does not provide a field-level merge editor for updated records."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private func keepLocalRecords(syncAfterResolution: Bool) async {
    if let sharingSyncCoordinator {
      let resolved = await sharingSyncCoordinator.resolveConflictByKeepingLocalRecords(
        review,
        syncAfterResolution: syncAfterResolution
      )
      resolutionMessage =
        resolved
        ? resolvedMessage(syncAfterResolution: syncAfterResolution)
        : "The conflict report could not be resolved."
    } else if conflictReviewStore?.resolve(review, choice: .keepLocalRecords) != nil {
      resolutionMessage = resolvedMessage(syncAfterResolution: false)
    } else {
      resolutionMessage = "The conflict report could not be resolved."
    }
  }

  private func acceptSharedDeletes(syncAfterResolution: Bool) async {
    guard let sharingSyncCoordinator else {
      resolutionMessage = "Accepting shared deletes requires the sharing sync coordinator."
      return
    }

    let resolved = await sharingSyncCoordinator.resolveConflictByAcceptingSharedDeletes(
      review,
      syncAfterResolution: syncAfterResolution
    )
    resolutionMessage =
      resolved
      ? acceptedDeleteMessage(syncAfterResolution: syncAfterResolution)
      : "The shared deletes could not be accepted."
  }

  private func resolvedMessage(syncAfterResolution: Bool) -> String {
    if syncAfterResolution {
      "Resolved by keeping local records. Shared-data sync was requested."
    } else {
      "Resolved by keeping local records. Run Sync Shared Data when ready."
    }
  }

  private func acceptedDeleteMessage(syncAfterResolution: Bool) -> String {
    if syncAfterResolution {
      "Resolved by accepting shared deletes. Affected local records were deleted and shared-data sync was requested."
    } else {
      "Resolved by accepting shared deletes. Affected local records were deleted. Run Sync Shared Data when ready."
    }
  }

  private func updatedRecords(for displayEntityName: String) -> [HerdSharingUpdatedRecordConflict] {
    review.updatedRecordConflicts
      .filter { $0.displayEntityName == displayEntityName }
      .sorted { lhs, rhs in
        if lhs.sharedModifiedAt != rhs.sharedModifiedAt {
          return lhs.sharedModifiedAt > rhs.sharedModifiedAt
        }
        return lhs.publicID.uuidString < rhs.publicID.uuidString
      }
  }

  private func conflicts(for displayEntityName: String) -> [HerdSharingPreventedDeleteConflict] {
    review.preventedDeleteConflicts
      .filter { $0.displayEntityName == displayEntityName }
      .sorted { lhs, rhs in
        if lhs.localModifiedAt != rhs.localModifiedAt {
          return lhs.localModifiedAt > rhs.localModifiedAt
        }
        return lhs.publicID.uuidString < rhs.publicID.uuidString
      }
  }

  private func formattedImportDate(_ date: Date) -> String {
    if date == .distantPast { return "Unavailable" }
    return formattedDate(date)
  }

  private func formattedDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .standard)
  }
}

#Preview {
  NavigationStack {
    HerdSharingConflictReviewDetailView(
      review: HerdSharingConflictReview(
        title: "Shared-data conflicts detected",
        sourceDescription: "Manual sync",
        detectedAt: .now,
        existingLocalRecordUpdateCount: 3,
        updatedRecordConflicts: [
          HerdSharingUpdatedRecordConflict(
            sourceEntityName: "SharedAnimalRecord",
            publicID: UUID(),
            localModifiedAt: .now,
            sharedModifiedAt: Date(timeIntervalSinceNow: -600)
          )
        ],
        preventedDeleteConflicts: [
          HerdSharingPreventedDeleteConflict(
            sourceEntityName: "SharedAnimalRecord",
            publicID: UUID(),
            localModifiedAt: .now,
            sharedDeletedAt: Date(timeIntervalSinceNow: -3_600)
          )
        ]
      )
    )
  }
}
