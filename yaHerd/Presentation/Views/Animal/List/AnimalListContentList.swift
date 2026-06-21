import SwiftUI

struct AnimalListContentList: View {
    let groupedAnimals: [AnimalSection]
    let shouldUseSections: Bool
    let batchMode: Bool
    @Binding var selectedAnimalIDs: Set<UUID>
    let hardDeleteOnSwipe: Bool
    @Binding var collapsedSectionIDs: Set<String>
    let onPrimarySwipeAction: (AnimalSummary) -> Void
    let onRestoreArchivedRecord: (AnimalSummary) -> Void

    var body: some View {
        List(selection: batchMode ? $selectedAnimalIDs : nil) {
            ForEach(groupedAnimals) { section in
                Section {
                    if !isCollapsed(section) {
                        sectionRows(section.animals)
                    }
                } header: {
                    sectionHeader(for: section)
                }
            }
        }
        .environment(\.editMode, .constant(batchMode ? .active : .inactive))
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func sectionHeader(for section: AnimalSection) -> some View {
        if shouldUseSections {
            Button {
                withAnimation(.snappy) {
                    toggleSection(section)
                }
            } label: {
                AnimalListSectionHeader(
                    title: section.title,
                    count: section.animals.count,
                    showsDisclosure: true,
                    isCollapsed: isCollapsed(section)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sectionHeaderAccessibilityLabel(for: section))
            .accessibilityValue(isCollapsed(section) ? "Collapsed" : "Expanded")
            .accessibilityHint("Double-tap to \(isCollapsed(section) ? "expand" : "collapse") this group")
        } else {
            AnimalListSectionHeader(
                title: nil,
                count: section.animals.count,
                showsDisclosure: false,
                isCollapsed: false
            )
        }
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
                .listRowBackground(Color.clear)
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

    private func isCollapsed(_ section: AnimalSection) -> Bool {
        shouldUseSections && collapsedSectionIDs.contains(section.id)
    }

    private func toggleSection(_ section: AnimalSection) {
        if collapsedSectionIDs.contains(section.id) {
            collapsedSectionIDs.remove(section.id)
        } else {
            collapsedSectionIDs.insert(section.id)
        }
    }

    private func sectionHeaderAccessibilityLabel(for section: AnimalSection) -> String {
        let countText = section.animals.count == 1 ? "1 animal" : "\(section.animals.count) animals"
        return "\(section.title), \(countText)"
    }
}

private struct AnimalListSectionHeader: View {
    let title: String?
    let count: Int
    let showsDisclosure: Bool
    let isCollapsed: Bool

    private var countText: String {
        count == 1 ? "1 animal" : "\(count) animals"
    }

    var body: some View {
        HStack(spacing: 8) {
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .accessibilityHidden(true)
            }

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: isCollapsed)
    }
}
