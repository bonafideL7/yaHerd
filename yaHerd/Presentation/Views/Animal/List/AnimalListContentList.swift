import SwiftUI

struct AnimalListContentList: View {
    let groupedAnimals: [AnimalSection]
    let shouldUseSections: Bool
    let batchMode: Bool
    @Binding var selectedAnimalIDs: Set<UUID>
    let hardDeleteOnSwipe: Bool
    let onPrimarySwipeAction: (AnimalSummary) -> Void
    let onRestoreArchivedRecord: (AnimalSummary) -> Void

    var body: some View {
        List(selection: batchMode ? $selectedAnimalIDs : nil) {
            ForEach(groupedAnimals) { section in
                Section {
                    sectionRows(section.animals)
                } header: {
                    AnimalListSectionHeader(
                        title: shouldUseSections ? section.title : nil,
                        count: section.animals.count
                    )
                }
            }
        }
        .environment(\.editMode, .constant(batchMode ? .active : .inactive))
        .listStyle(.insetGrouped)
        .scrollContentBackground(.automatic)
    }

    @ViewBuilder
    private func sectionRows(_ animals: [AnimalSummary]) -> some View {
        ForEach(animals) { animal in
            if batchMode {
                AnimalListRowContent(animal: animal)
                    .tag(animal.id)
                    .listRowBackground(batchRowBackground(for: animal))
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width }
            } else {
                NavigationLink(value: animal.id) {
                    AnimalListRowContent(animal: animal)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    trailingSwipeActions(for: animal)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if animal.isArchived {
                        Button {
                            onRestoreArchivedRecord(animal)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.blue)
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width }
            }
        }
    }

    @ViewBuilder
    private func trailingSwipeActions(for animal: AnimalSummary) -> some View {
        if animal.isArchived || hardDeleteOnSwipe {
            Button(role: .destructive) {
                onPrimarySwipeAction(animal)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } else {
            Button {
                onPrimarySwipeAction(animal)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func batchRowBackground(for animal: AnimalSummary) -> some View {
        if selectedAnimalIDs.contains(animal.id) {
            Color.accentColor.opacity(0.14)
        } else {
            Color.clear
        }
    }
}

private struct AnimalListSectionHeader: View {
    let title: String?
    let count: Int

    private var countText: String {
        count == 1 ? "1 animal" : "\(count) animals"
    }

    var body: some View {
        HStack(spacing: 8) {
            if let title {
                Text(title)
            } else {
                Text(countText)
            }

            if title != nil {
                Spacer(minLength: 12)
                Text(countText)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
        .textCase(.uppercase)
    }
}
