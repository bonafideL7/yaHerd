//
//  HerdSharingConflictResolutionDetailView.swift
//  yaHerd
//

import SwiftUI

struct HerdSharingConflictResolutionDetailView: View {
  let resolution: HerdSharingConflictResolution

  var body: some View {
    List {
      summarySection
      restoredFieldsSection
      updatedRecordsSection
      skippedDeletesSection
      notesSection
    }
    .navigationTitle("Resolution Detail")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var summarySection: some View {
    Section("Resolution") {
      LabeledContent("Action", value: resolution.choice.displayName)
      LabeledContent("Resolved", value: formattedDate(resolution.resolvedAt))
      LabeledContent("Source", value: resolution.sourceDescription)
      LabeledContent("Affected Records", value: resolution.affectedRecordCount.formatted())
      if resolution.restoredLocalFieldCount > 0 {
        LabeledContent("Restored Fields", value: resolution.restoredLocalFieldCount.formatted())
      }

      Text(resolution.choice.summary)
        .font(.caption)
        .foregroundStyle(.secondary)

      Text(resolution.conflictSummary)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var restoredFieldsSection: some View {
    Section("Restored Local Fields") {
      if resolution.restoredLocalFieldSelections.isEmpty {
        ContentUnavailableView(
          "No Restored Fields",
          systemImage: "arrow.uturn.backward.circle",
          description: Text("This resolution did not restore individual pre-import local field values.")
        )
      } else {
        ForEach(restoredFieldEntitySummaries, id: \.entityName) { summary in
          DisclosureGroup("\(displayEntityName(summary.entityName)) (\(summary.selections.count))") {
            ForEach(summary.selections) { selection in
              VStack(alignment: .leading, spacing: 4) {
                Text(selection.fieldName)
                  .font(.caption.weight(.semibold))
                Text(selection.publicID.uuidString)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .textSelection(.enabled)
              }
              .padding(.vertical, 2)
            }
          }
        }
      }
    }
  }

  private var updatedRecordsSection: some View {
    Section("Updated Existing Records") {
      if resolution.updatedRecordConflicts.isEmpty {
        if resolution.existingLocalRecordUpdateCount > 0 {
          Text(
            "This older resolution only stored the updated-record count: \(resolution.existingLocalRecordUpdateCount)."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        } else {
          ContentUnavailableView(
            "No Updated Records",
            systemImage: "checkmark.circle",
            description: Text("This resolution did not involve imported shared updates.")
          )
        }
      } else {
        ForEach(updatedRecordEntitySummaries, id: \.entityName) { summary in
          DisclosureGroup("\(displayEntityName(summary.entityName)) (\(summary.conflicts.count))") {
            ForEach(summary.conflicts) { conflict in
              VStack(alignment: .leading, spacing: 6) {
                Text(conflict.publicID.uuidString)
                  .font(.caption.weight(.semibold))
                  .textSelection(.enabled)

                LabeledContent("Local modified", value: formattedImportDate(conflict.localModifiedAt))
                  .font(.caption2)
                LabeledContent("Shared mirrored", value: formattedImportDate(conflict.sharedModifiedAt))
                  .font(.caption2)

                if !conflict.fieldChanges.isEmpty {
                  DisclosureGroup("Changed Fields (\(conflict.changedFieldCount))") {
                    ForEach(conflict.fieldChanges) { fieldChange in
                      VStack(alignment: .leading, spacing: 3) {
                        Text(fieldChange.fieldName)
                          .font(.caption2.weight(.semibold))
                        Text("Local (\(fieldChange.localValue.displayType)): \(fieldChange.localValueDescription)")
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                          .textSelection(.enabled)
                        Text("Shared (\(fieldChange.sharedValue.displayType)): \(fieldChange.sharedValueDescription)")
                          .font(.caption2)
                          .foregroundStyle(.secondary)
                          .textSelection(.enabled)
                      }
                      .padding(.vertical, 2)
                    }
                  }
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
      if resolution.preventedDeleteConflicts.isEmpty {
        if resolution.preventedDeleteCount > 0 {
          Text(
            "This older resolution only stored the skipped-delete count: \(resolution.preventedDeleteCount)."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        } else {
          ContentUnavailableView(
            "No Shared Deletes",
            systemImage: "trash.slash",
            description: Text("This resolution did not involve skipped shared deletes.")
          )
        }
      } else {
        ForEach(preventedDeleteEntitySummaries, id: \.entityName) { summary in
          DisclosureGroup("\(displayEntityName(summary.entityName)) (\(summary.conflicts.count))") {
            ForEach(summary.conflicts) { conflict in
              VStack(alignment: .leading, spacing: 6) {
                Text(conflict.publicID.uuidString)
                  .font(.caption.weight(.semibold))
                  .textSelection(.enabled)

                LabeledContent("Local edit", value: formattedDate(conflict.localModifiedAt))
                  .font(.caption2)
                LabeledContent("Shared delete", value: formattedDate(conflict.sharedDeletedAt))
                  .font(.caption2)
              }
              .padding(.vertical, 4)
            }
          }
        }
      }
    }
  }

  private var notesSection: some View {
    Section("Audit Notes") {
      Text(
        "Resolution history is stored locally for review. It records the selected resolution action and a snapshot of the conflict report as it existed when the action was taken."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private var restoredFieldEntitySummaries:
    [(entityName: String, selections: [HerdSharingLocalFieldRestoreSelection])]
  {
    Dictionary(grouping: resolution.restoredLocalFieldSelections, by: \.sourceEntityName)
      .map { entityName, selections in
        (entityName, selections.sorted { lhs, rhs in
          if lhs.publicID != rhs.publicID {
            return lhs.publicID.uuidString < rhs.publicID.uuidString
          }
          return lhs.fieldName < rhs.fieldName
        })
      }
      .sorted { lhs, rhs in
        if lhs.selections.count != rhs.selections.count { return lhs.selections.count > rhs.selections.count }
        return displayEntityName(lhs.entityName) < displayEntityName(rhs.entityName)
      }
  }

  private var updatedRecordEntitySummaries:
    [(entityName: String, conflicts: [HerdSharingUpdatedRecordConflict])]
  {
    Dictionary(grouping: resolution.updatedRecordConflicts, by: \.sourceEntityName)
      .map { entityName, conflicts in
        (entityName, conflicts.sorted { lhs, rhs in
          if lhs.sharedModifiedAt != rhs.sharedModifiedAt {
            return lhs.sharedModifiedAt > rhs.sharedModifiedAt
          }
          return lhs.publicID.uuidString < rhs.publicID.uuidString
        })
      }
      .sorted { lhs, rhs in
        if lhs.conflicts.count != rhs.conflicts.count { return lhs.conflicts.count > rhs.conflicts.count }
        return displayEntityName(lhs.entityName) < displayEntityName(rhs.entityName)
      }
  }

  private var preventedDeleteEntitySummaries:
    [(entityName: String, conflicts: [HerdSharingPreventedDeleteConflict])]
  {
    Dictionary(grouping: resolution.preventedDeleteConflicts, by: \.sourceEntityName)
      .map { entityName, conflicts in
        (entityName, conflicts.sorted { lhs, rhs in
          if lhs.localModifiedAt != rhs.localModifiedAt {
            return lhs.localModifiedAt > rhs.localModifiedAt
          }
          return lhs.publicID.uuidString < rhs.publicID.uuidString
        })
      }
      .sorted { lhs, rhs in
        if lhs.conflicts.count != rhs.conflicts.count { return lhs.conflicts.count > rhs.conflicts.count }
        return displayEntityName(lhs.entityName) < displayEntityName(rhs.entityName)
      }
  }

  private func displayEntityName(_ sourceEntityName: String) -> String {
    sourceEntityName
      .replacingOccurrences(of: "Shared", with: "")
      .replacingOccurrences(of: "Record", with: "")
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
    HerdSharingConflictResolutionDetailView(
      resolution: HerdSharingConflictResolution(
        review: HerdSharingConflictReview(
          title: "Shared-data conflicts detected",
          sourceDescription: "Manual sync",
          detectedAt: .now,
          existingLocalRecordUpdateCount: 1,
          updatedRecordConflicts: [
            HerdSharingUpdatedRecordConflict(
              sourceEntityName: "SharedAnimalRecord",
              publicID: UUID(),
              localModifiedAt: .now,
              sharedModifiedAt: Date(timeIntervalSinceNow: -600),
              fieldChanges: [
                HerdSharingUpdatedRecordFieldChange(
                  fieldName: "name",
                  localValue: .string("Local Cow"),
                  sharedValue: .string("Shared Cow")
                )
              ]
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
        ),
        choice: .restoreLocalFields,
        restoredLocalFieldSelections: [
          HerdSharingLocalFieldRestoreSelection(
            sourceEntityName: "SharedAnimalRecord",
            publicID: UUID(),
            fieldName: "name"
          )
        ]
      )
    )
  }
}
