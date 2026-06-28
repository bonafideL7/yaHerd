//
//  AnimalDetailRecordManagementSection.swift
//

import SwiftUI

struct AnimalDetailRecordManagementSection: View {
    let detail: AnimalDetailSnapshot
    let hardDeleteOnSwipe: Bool
    let onRestore: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var showingArchiveConfirmation = false
    @State private var showingHardDeleteConfirmation = false

    var body: some View {
        archiveSection
        hardDeleteSection
    }

    private var archiveSection: some View {
        Section {
            if detail.isArchived {
                Button(action: onRestore) {
                    Label("Restore Archived Record", systemImage: "arrow.uturn.backward.circle.fill")
                }
            } else {
                Button(role: .destructive) {
                    showingArchiveConfirmation = true
                } label: {
                    Label("Archive Record", systemImage: "archivebox")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.orange)
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

    private var hardDeleteSection: some View {
        Section {
            Button("Permanently Delete", role: .destructive) {
                showingHardDeleteConfirmation = true
            }
            .alert("Permanently delete this animal?", isPresented: $showingHardDeleteConfirmation) {
                Button("Delete Permanently", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the animal and all related records from the app.")
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            Text(hardDeleteFooterText)
        }
    }

    private var hardDeleteFooterText: String {
        if hardDeleteOnSwipe {
            "Swipe actions on the animal list permanently delete records while this setting is enabled."
        } else {
            "Permanent delete removes the animal and all related records from the app."
        }
    }
}
