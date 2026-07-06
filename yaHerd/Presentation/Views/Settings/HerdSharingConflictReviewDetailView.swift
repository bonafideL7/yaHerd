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
      if review.existingLocalRecordUpdateCount > 0 {
        Text(
          "These records already existed in SwiftData and were updated from shared bridge data during import. yaHerd reports the count, but this pass does not track field-level before/after values."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        ContentUnavailableView(
          "No Updated Local Records",
          systemImage: "checkmark.circle",
          description: Text(
            "This report did not include existing SwiftData records updated from shared data."
          )
        )
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

      if let resolutionMessage {
        Text(resolutionMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(
        "Keep Local Records resolves this local conflict report and preserves the resolution in Settings history. The sync option immediately runs shared-data sync so the kept local records can be exported back through the Core Data sharing bridge."
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
        "This screen can resolve the report by keeping local records. It still does not provide a field-level merge editor. To accept a collaborator's delete instead, delete the affected record through the normal yaHerd screen and run Sync Shared Data."
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

  private func resolvedMessage(syncAfterResolution: Bool) -> String {
    if syncAfterResolution {
      "Resolved by keeping local records. Shared-data sync was requested."
    } else {
      "Resolved by keeping local records. Run Sync Shared Data when ready."
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
