//
//  HerdSharingConflictReviewDetailView.swift
//  yaHerd
//

import SwiftUI

struct HerdSharingConflictReviewDetailView: View {
  @Environment(\.herdSharingConflictReviewStore) private var conflictReviewStore
  @Environment(\.herdSharingSyncCoordinator) private var sharingSyncCoordinator
  @State private var resolutionMessage: String?
  @State private var selectedLocalFieldRestoreIDs: Set<String> = []

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

                LabeledContent(
                  "Local modified", value: formattedImportDate(conflict.localModifiedAt)
                )
                .font(.caption2)
                LabeledContent(
                  "Shared mirrored", value: formattedImportDate(conflict.sharedModifiedAt)
                )
                .font(.caption2)

                if conflict.fieldChanges.isEmpty {
                  Text(
                    "This existing SwiftData record was overwritten from the accepted shared bridge record during import. No changed scalar fields were captured."
                  )
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                } else {
                  DisclosureGroup("Changed Fields (\(conflict.changedFieldCount))") {
                    if conflict.supportsLocalFieldRestore {
                      DisclosureGroup(
                        "Restorable Fields (\(conflict.supportedLocalRestoreFieldChanges.count))"
                      ) {
                        ForEach(conflict.supportedLocalRestoreFieldChanges) { fieldChange in
                          restorableFieldChangeRow(fieldChange, in: conflict)
                        }
                      }
                    }

                    if conflict.hasReviewOnlyFieldChanges {
                      DisclosureGroup("Review Only Fields (\(conflict.reviewOnlyFieldChanges.count))") {
                        ForEach(conflict.reviewOnlyFieldChanges) { fieldChange in
                          reviewOnlyFieldChangeRow(fieldChange)
                        }
                      }
                    }
                  }
                  .font(.caption2)
                }
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

      Button {
        Task {
          await restoreSelectedLocalFields(
            syncAfterResolution: true,
            resolveAfterRestore: true
          )
        }
      } label: {
        Label(
          "Restore Selected Local Fields, Mark Resolved, and Sync",
          systemImage: "arrow.uturn.backward.icloud"
        )
      }
      .disabled(
        selectedLocalFieldRestoreIDs.isEmpty || sharingSyncCoordinator == nil
          || sharingSyncCoordinator?.isSyncing == true)

      Button {
        Task {
          await restoreSelectedLocalFields(
            syncAfterResolution: false,
            resolveAfterRestore: true
          )
        }
      } label: {
        Label(
          "Restore Selected Local Fields and Mark Resolved",
          systemImage: "checkmark.circle"
        )
      }
      .disabled(selectedLocalFieldRestoreIDs.isEmpty || sharingSyncCoordinator == nil)

      Button {
        Task {
          await restoreSelectedLocalFields(
            syncAfterResolution: false,
            resolveAfterRestore: false
          )
        }
      } label: {
        Label("Restore Selected Local Fields Only", systemImage: "arrow.uturn.backward.circle")
      }
      .disabled(selectedLocalFieldRestoreIDs.isEmpty || sharingSyncCoordinator == nil)

      Button {
        Task { await acceptSharedUpdates(syncAfterResolution: true) }
      } label: {
        Label("Accept Shared Updates and Sync", systemImage: "checkmark.icloud")
      }
      .disabled(
        review.updatedRecordConflictCount == 0 && review.existingLocalRecordUpdateCount == 0
          || sharingSyncCoordinator == nil
          || sharingSyncCoordinator?.isSyncing == true)

      Button {
        Task { await acceptSharedUpdates(syncAfterResolution: false) }
      } label: {
        Label("Accept Shared Updates", systemImage: "checkmark.circle")
      }
      .disabled(
        review.updatedRecordConflictCount == 0 && review.existingLocalRecordUpdateCount == 0
          || sharingSyncCoordinator == nil)

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
        "Restore Selected Local Fields writes selected pre-import local values back into SwiftData for supported scalar fields. Use the Mark Resolved option when the selected restores fully address the conflict. Accept Shared Updates keeps the imported shared values already written to SwiftData. Keep Local Records preserves local intent and should be followed by shared-data sync. Accept Shared Deletes deletes the affected local SwiftData records by public ID."
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
        "Restorable Fields can be written back to SwiftData from this screen. Review Only Fields are shown for comparison but are not written back because they are relationships, arrays, or unsupported values."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func restorableFieldChangeRow(
    _ fieldChange: HerdSharingUpdatedRecordFieldChange,
    in conflict: HerdSharingUpdatedRecordConflict
  ) -> some View {
    let selection = conflict.restoreSelection(for: fieldChange)
    let isSelected = selectedLocalFieldRestoreIDs.contains(selection.id)

    fieldChangeValueRows(fieldChange) {
      Button {
        toggleLocalFieldRestore(selection)
      } label: {
        Label(
          isSelected ? "Selected" : "Restore Local",
          systemImage: isSelected ? "checkmark.circle.fill" : "arrow.uturn.backward.circle"
        )
      }
      .buttonStyle(.borderless)
      .font(.caption2)
    }
  }

  @ViewBuilder
  private func reviewOnlyFieldChangeRow(
    _ fieldChange: HerdSharingUpdatedRecordFieldChange
  ) -> some View {
    fieldChangeValueRows(fieldChange) {
      Text("Review only")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func fieldChangeValueRows<Action: View>(
    _ fieldChange: HerdSharingUpdatedRecordFieldChange,
    @ViewBuilder action: () -> Action
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(fieldChange.fieldName)
          .font(.caption2.weight(.semibold))

        Spacer()

        action()
      }

      Text(
        "Local (\(fieldChange.localValue.displayType)): \(fieldChange.localValueDescription)"
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      .textSelection(.enabled)
      Text(
        "Shared (\(fieldChange.sharedValue.displayType)): \(fieldChange.sharedValueDescription)"
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      .textSelection(.enabled)
    }
    .padding(.vertical, 2)
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

  private func toggleLocalFieldRestore(_ selection: HerdSharingLocalFieldRestoreSelection) {
    if selectedLocalFieldRestoreIDs.contains(selection.id) {
      selectedLocalFieldRestoreIDs.remove(selection.id)
    } else {
      selectedLocalFieldRestoreIDs.insert(selection.id)
    }
  }

  private func restoreSelectedLocalFields(
    syncAfterResolution: Bool,
    resolveAfterRestore: Bool
  ) async {
    guard let sharingSyncCoordinator else {
      resolutionMessage = "Restoring local fields requires the sharing sync coordinator."
      return
    }

    let selections = selectedLocalFieldRestoreSelections
    guard !selections.isEmpty else {
      resolutionMessage = "Select one or more supported local field values to restore."
      return
    }

    let restored = await sharingSyncCoordinator.restoreLocalFieldsFromConflict(
      selections,
      in: review,
      syncAfterResolution: syncAfterResolution,
      resolveAfterRestore: resolveAfterRestore
    )
    resolutionMessage =
      restored
      ? restoredLocalFieldsMessage(
        count: selections.count,
        syncAfterResolution: syncAfterResolution,
        resolveAfterRestore: resolveAfterRestore
      )
      : "The selected local fields could not be restored."

    if restored {
      selectedLocalFieldRestoreIDs.removeAll()
    }
  }

  private func acceptSharedUpdates(syncAfterResolution: Bool) async {
    guard let sharingSyncCoordinator else {
      if conflictReviewStore?.resolve(review, choice: .acceptSharedUpdates) != nil {
        resolutionMessage = acceptedSharedUpdatesMessage(syncAfterResolution: false)
      } else {
        resolutionMessage = "The shared updates could not be accepted."
      }
      return
    }

    let resolved = await sharingSyncCoordinator.resolveConflictByAcceptingSharedUpdates(
      review,
      syncAfterResolution: syncAfterResolution
    )
    resolutionMessage =
      resolved
      ? acceptedSharedUpdatesMessage(syncAfterResolution: syncAfterResolution)
      : "The shared updates could not be accepted."
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

  private func restoredLocalFieldsMessage(
    count: Int,
    syncAfterResolution: Bool,
    resolveAfterRestore: Bool
  ) -> String {
    if resolveAfterRestore && syncAfterResolution {
      "Restored \(count) selected local field value(s), marked the conflict resolved, and requested shared-data sync."
    } else if resolveAfterRestore {
      "Restored \(count) selected local field value(s) and marked the conflict resolved. Run Sync Shared Data when ready."
    } else {
      "Restored \(count) selected local field value(s). The conflict report remains open for more review."
    }
  }

  private func acceptedSharedUpdatesMessage(syncAfterResolution: Bool) -> String {
    if syncAfterResolution {
      "Resolved by accepting shared updates. Imported shared values were kept and shared-data sync was requested."
    } else {
      "Resolved by accepting shared updates. Imported shared values were kept."
    }
  }

  private func acceptedDeleteMessage(syncAfterResolution: Bool) -> String {
    if syncAfterResolution {
      "Resolved by accepting shared deletes. Affected local records were deleted and shared-data sync was requested."
    } else {
      "Resolved by accepting shared deletes. Affected local records were deleted. Run Sync Shared Data when ready."
    }
  }

  private var selectedLocalFieldRestoreSelections: [HerdSharingLocalFieldRestoreSelection] {
    review.updatedRecordConflicts
      .flatMap { conflict in
        conflict.supportedLocalRestoreFieldChanges.map { conflict.restoreSelection(for: $0) }
      }
      .filter { selectedLocalFieldRestoreIDs.contains($0.id) }
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
