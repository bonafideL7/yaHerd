//
//  AnimalDetailReadOnlySections.swift
//

import SwiftUI

struct AnimalDetailOverviewSection: View {
    let detail: AnimalDetailSnapshot

    var body: some View {
        Section("Overview") {
            if !detail.name.isEmpty {
                LabeledContent("Name") {
                    Text(detail.name.nilIfEmpty ?? "—")
                }
            }

            LabeledContent("Birth Date") {
                Text(detail.birthDate.formatted(date: .abbreviated, time: .omitted))
            }

            LabeledContent("Sex") {
                Text(detail.sex.label)
            }

            LabeledContent("Pasture") {
                Text(detail.pastureName ?? "None")
            }
        }
    }
}

struct AnimalDetailTagsSection: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let detail: AnimalDetailSnapshot

    var body: some View {
        Section("Tags") {
            if detail.activeTags.isEmpty {
                Text("No active tags")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.activeTags) { tag in
                    tagRow(for: tag)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .alignmentGuide(.listRowSeparatorTrailing) { d in d.width }
                }
            }

            if !detail.inactiveTags.isEmpty {
                DisclosureGroup("Retired Tags (\(detail.inactiveTags.count))") {
                    ForEach(detail.inactiveTags) { tag in
                        VStack(alignment: .leading, spacing: 4) {
                            tagBadge(for: tag)
                                .opacity(0.65)

                            if let removedAt = tag.removedAt {
                                Text("Retired \(removedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func tagRow(for tag: AnimalTagSnapshot) -> some View {
        HStack {
            tagBadge(for: tag)
            Spacer()
            if tag.isPrimary {
                Label("Primary", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tagBadge(for tag: AnimalTagSnapshot) -> some View {
        let def = tagColorLibrary.resolvedDefinition(tagColorID: tag.colorID)
        return AnimalTagView(
            tagNumber: tag.normalizedNumber,
            color: def.color,
            colorName: def.name,
            size: .compact
        )
    }
}

struct AnimalDetailStatusSection: View {
    let detail: AnimalDetailSnapshot
    let onBeginEditingStatus: (AnimalStatus) -> Void

    var body: some View {
        Section("Status") {
            HStack {
                Text("Current Status")
                Spacer()
                Label(detail.status.label, systemImage: detail.status.systemImage)
                    .fontWeight(.semibold)
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .alignmentGuide(.listRowSeparatorTrailing) { d in d.width }

            if let statusReferenceName = detail.statusReferenceName {
                LabeledContent("Status Reference") {
                    Text(statusReferenceName)
                        .fontWeight(.medium)
                }
            }

            if detail.isArchived {
                HStack {
                    Text("Record State")
                    Spacer()
                    Label("Archived", systemImage: "archivebox.fill")
                        .foregroundStyle(.orange)
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .alignmentGuide(.listRowSeparatorTrailing) { d in d.width }

                if let archivedAt = detail.archivedAt {
                    LabeledContent("Archived On") {
                        Text(archivedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }

            switch detail.status {
            case .active:
                EmptyView()
            case .sold:
                LabeledContent("Sale Date") {
                    Text((detail.saleDate ?? .now).formatted(date: .abbreviated, time: .omitted))
                }

                LabeledContent("Sale Price") {
                    Text(
                        detail.salePrice?.formatted(
                            .currency(code: Locale.current.currency?.identifier ?? "USD")
                        ) ?? "—"
                    )
                }

                if let reasonSold = detail.reasonSold, !reasonSold.isEmpty {
                    LabeledContent("Reason Sold") {
                        Text(reasonSold)
                            .multilineTextAlignment(.trailing)
                    }
                }
            case .dead:
                LabeledContent("Death Date") {
                    Text((detail.deathDate ?? .now).formatted(date: .abbreviated, time: .omitted))
                }

                if let causeOfDeath = detail.causeOfDeath, !causeOfDeath.isEmpty {
                    LabeledContent("Cause of Death") {
                        Text(causeOfDeath)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            AnimalDetailStatusActionButtons(detail: detail, onBeginEditingStatus: onBeginEditingStatus)
        }
    }
}

private struct AnimalDetailStatusActionButtons: View {
    let detail: AnimalDetailSnapshot
    let onBeginEditingStatus: (AnimalStatus) -> Void

    var body: some View {
        switch detail.status {
        case .active:
            Button {
                onBeginEditingStatus(.sold)
            } label: {
                Label("Mark Sold", systemImage: AnimalStatus.sold.systemImage)
            }

            Button {
                onBeginEditingStatus(.dead)
            } label: {
                Label("Mark Dead", systemImage: AnimalStatus.dead.systemImage)
            }

        case .sold:
            Button {
                onBeginEditingStatus(.active)
            } label: {
                Label("Return to Active", systemImage: AnimalStatus.active.systemImage)
            }

            Button {
                onBeginEditingStatus(.dead)
            } label: {
                Label("Correct to Dead", systemImage: AnimalStatus.dead.systemImage)
            }

        case .dead:
            Button {
                onBeginEditingStatus(.active)
            } label: {
                Label("Correct to Active", systemImage: AnimalStatus.active.systemImage)
            }

            Button {
                onBeginEditingStatus(.sold)
            } label: {
                Label("Correct to Sold", systemImage: AnimalStatus.sold.systemImage)
            }
        }
    }
}

struct AnimalDetailLineageSection: View {
    @Binding var isExpanded: Bool
    let detail: AnimalDetailSnapshot

    var body: some View {
        let dam = detail.dam?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sire = detail.sire?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDam = !(dam ?? "").isEmpty
        let hasSire = !(sire ?? "").isEmpty

        if hasDam || hasSire {
            Section {
                DisclosureGroup("Parents", isExpanded: $isExpanded) {
                    if let dam, !dam.isEmpty {
                        LabeledContent("Dam") { Text(dam) }
                    }
                    if let sire, !sire.isEmpty {
                        LabeledContent("Sire") { Text(sire) }
                    }
                }
            }
        }
    }
}

struct AnimalDetailDistinguishingFeaturesSection: View {
    let detail: AnimalDetailSnapshot

    var body: some View {
        if !detail.distinguishingFeatures.isEmpty {
            Section("Distinguishing Features") {
                ForEach(detail.distinguishingFeatures) { feature in
                    Text(feature.description)
                }
            }
        }
    }
}

struct AnimalDetailRecordManagementSection: View {
    let detail: AnimalDetailSnapshot
    let hardDeleteOnSwipe: Bool
    let onRestore: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var showingArchiveConfirmation = false
    @State private var showingHardDeleteConfirmation = false

    var body: some View {
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
            if hardDeleteOnSwipe {
                Text("Swipe actions on the animal list permanently delete records while this setting is enabled.")
            } else {
                Text("Permanent delete removes the animal and all related records from the app.")
            }
        }
    }
}
