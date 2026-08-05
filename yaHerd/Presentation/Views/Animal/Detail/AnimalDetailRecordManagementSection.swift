//
//  AnimalDetailRecordManagementSection.swift
//

import SwiftUI

struct AnimalDetailRecordManagementSection: View {
    let detail: AnimalDetailSnapshot
    let onRestore: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var showingArchiveConfirmation = false
    @State private var showingPermanentDeleteReview = false

    var body: some View {
        archiveSection

        if detail.isArchived {
            permanentDeleteSection
        }
    }

    private var archiveSection: some View {
        Section {
            if detail.isArchived {
                Button(action: onRestore) {
                    Label("Restore Archived Record", systemImage: "arrow.uturn.backward.circle.fill")
                }
                .disabledWhenDataReadOnly()
            } else {
                Button(role: .destructive) {
                    showingArchiveConfirmation = true
                } label: {
                    Label("Archive Record", systemImage: "archivebox")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.orange)
                .disabledWhenDataReadOnly()
                .confirmationDialog(
                    "Archive this record?",
                    isPresented: $showingArchiveConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Archive Record", role: .destructive, action: onArchive)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Archived records are hidden from normal herd views but can be restored later.")
                }
            }
        } header: {
            Text("Record Management")
        } footer: {
            Text("Archiving hides the record from normal herd views without changing the animal's herd status.")
        }
    }

    private var permanentDeleteSection: some View {
        Section {
            Button("Permanently Delete", role: .destructive) {
                showingPermanentDeleteReview = true
            }
            .disabledWhenDataReadOnly()
            .sheet(isPresented: $showingPermanentDeleteReview) {
                AnimalPermanentDeleteReviewView(
                    detail: detail,
                    onDelete: onDelete
                )
                .presentationDetents([.large])
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Permanent deletion is available only after archiving. Review the affected records before confirming.")
        }
    }
}

private struct AnimalPermanentDeleteReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let detail: AnimalDetailSnapshot
    let onDelete: () -> Void

    private var tagCount: Int {
        detail.activeTags.count + detail.inactiveTags.count
    }

    private var maternalOffspringCount: Int {
        detail.maternalOffspring.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This cannot be undone. The animal record will be removed from every device that shares this herd.")
                        .foregroundStyle(.secondary)
                }

                Section("Records Deleted With This Animal") {
                    impactRow(
                        title: "Animal record",
                        detail: "Identity, status, location, and archive information"
                    )
                    impactRow(
                        title: countLabel(tagCount, singular: "tag", plural: "tags"),
                        detail: "Active and retired tag records"
                    )
                    impactRow(
                        title: "Health and pregnancy history",
                        detail: "All health records and pregnancy checks owned by this animal"
                    )
                    impactRow(
                        title: "Movement and status history",
                        detail: "All pasture movement and status-change records"
                    )
                }

                Section("Related Records Kept Without This Animal") {
                    impactRow(
                        title: relationshipTitle,
                        detail: "Parent and offspring links are cleared"
                    )
                    impactRow(
                        title: "Working-session records",
                        detail: "Queue items and treatment records remain but lose the animal link"
                    )
                    impactRow(
                        title: "Field-check records",
                        detail: "Animal checks and findings remain but lose the animal link"
                    )
                    impactRow(
                        title: "Pregnancy-check sire references",
                        detail: "Checks that name this animal as sire remain but the sire link is cleared"
                    )
                }
            }
            .navigationTitle("Permanent Delete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete Permanently", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var relationshipTitle: String {
        guard maternalOffspringCount > 0 else {
            return "Parent and offspring relationships"
        }
        return "Parent links and \(countLabel(maternalOffspringCount, singular: "maternal offspring", plural: "maternal offspring"))"
    }

    private func impactRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func countLabel(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
