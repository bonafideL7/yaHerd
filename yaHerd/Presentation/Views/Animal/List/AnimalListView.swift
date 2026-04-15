//
//  AnimalListView.swift
//

import SwiftUI

#Preview {
    AnimalListView()
        .preferredColorScheme(.dark)
}

struct AnimalListView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("allowHardDelete") private var hardDeleteOnSwipe = false

    @State private var viewModel = AnimalListViewModel()
    @State private var searchText = ""
    @State private var sortOrder: AnimalSortOrder = .tagAscending
    @State private var showingAdd = false
    @State private var showingFilters = false
    @State private var filter = AnimalFilter()
    @State private var showRemovedStatuses = false
    @State private var showArchivedRecords = false
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var batchMode = false
    @State private var selectedAnimalIDs: Set<UUID> = []
    @State private var showingPasturePicker = false

    private var repository: any AnimalRepository { dependencies.animalRepository }

    private var filteredAndSortedAnimals: [AnimalSummary] {
        AnimalListDerivations.filteredAndSortedAnimals(
            items: viewModel.items,
            searchText: searchText,
            sortOrder: sortOrder,
            filter: filter,
            showRemovedStatuses: showRemovedStatuses,
            showArchivedRecords: showArchivedRecords
        ) { tagNumber, colorID in
            tagColorLibrary.formattedTag(tagNumber: tagNumber, colorID: colorID)
        }
    }

    private var groupedAnimals: [AnimalSection] {
        AnimalListDerivations.groupedAnimals(filteredAndSortedAnimals, sortOrder: sortOrder)
    }

    private var shouldUseSections: Bool {
        AnimalListDerivations.shouldUseSections(for: sortOrder)
    }

    private var emptyStateConfiguration: AnimalListEmptyStateConfiguration {
        AnimalListDerivations.emptyStateConfiguration(
            items: viewModel.items,
            searchText: searchText,
            filter: filter,
            showRemovedStatuses: showRemovedStatuses,
            showArchivedRecords: showArchivedRecords
        )
    }

    private var hasHiddenOffHerdAnimals: Bool {
        AnimalListDerivations.hasHiddenOffHerdAnimals(items: viewModel.items)
    }

    private var hasHiddenArchivedRecords: Bool {
        AnimalListDerivations.hasHiddenArchivedRecords(items: viewModel.items)
    }

    var body: some View {
        Group {
            if filteredAndSortedAnimals.isEmpty {
                emptyStateView
            } else {
                herdList
            }
        }
        .navigationTitle("YaHerd")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: UUID.self) { AnimalDetailView(animalID: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(batchMode ? "Done" : "Select") {
                    withAnimation(.snappy) {
                        batchMode.toggle()
                        if !batchMode {
                            selectedAnimalIDs.removeAll()
                        }
                    }
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Animal")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomOverlay }
        .sheet(isPresented: $showingAdd, onDismiss: reload) { AddAnimalView() }
        .sheet(isPresented: $showingFilters) {
            AnimalFilterView(
                filter: $filter,
                showRemovedStatuses: $showRemovedStatuses,
                showArchivedRecords: $showArchivedRecords,
                pastureOptions: viewModel.pastureOptions
            )
        }
        .sheet(isPresented: $showingPasturePicker) {
            PastureTilePickerView { pasture in
                viewModel.move(ids: Array(selectedAnimalIDs), toPastureID: pasture.id, using: repository)
                selectedAnimalIDs.removeAll()
                batchMode = false
            }
        }
        .onAppear(perform: reload)
        .animation(.snappy, value: batchMode)
        .animation(.snappy, value: selectedAnimalIDs.count)
        .animation(.snappy, value: currentFilterChips.count)
    }

    private var herdList: some View {
        AnimalListContentList(
            groupedAnimals: groupedAnimals,
            shouldUseSections: shouldUseSections,
            batchMode: batchMode,
            selectedAnimalIDs: $selectedAnimalIDs,
            hardDeleteOnSwipe: hardDeleteOnSwipe,
            onPrimarySwipeAction: performPrimarySwipeAction,
            onRestoreArchivedRecord: restoreArchivedRecord
        )
    }

    private var emptyStateView: some View {
        AnimalListEmptyStateView(
            configuration: emptyStateConfiguration,
            hasItems: !viewModel.items.isEmpty,
            filtersAreActive: filter.isActive || showRemovedStatuses || showArchivedRecords,
            hasHiddenOffHerdAnimals: hasHiddenOffHerdAnimals,
            hasHiddenArchivedRecords: hasHiddenArchivedRecords,
            showRemovedStatuses: showRemovedStatuses,
            showArchivedRecords: showArchivedRecords,
            colorScheme: colorScheme,
            onAddAnimal: { showingAdd = true },
            onAddSampleData: {
                dependencies.seedSampleDataIfNeeded()
                reload()
            },
            onClearFilters: clearAllFilters,
            onShowInactive: { showRemovedStatuses = true },
            onShowArchivedRecords: { showArchivedRecords = true }
        )
    }

    private var bottomOverlay: some View {
        VStack(spacing: 10) {
            if batchMode {
                batchActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                floatingControlBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var floatingControlBar: some View {
        AnimalListFloatingControlBar(
            isSearching: $isSearching,
            searchText: $searchText,
            sortOrder: $sortOrder,
            filtersAreActive: filter.isActive || showRemovedStatuses || showArchivedRecords,
            filterChipCount: currentFilterChips.count,
            hasAnyActiveCriteria: hasAnyActiveCriteria,
            chips: currentFilterChips,
            onShowFilters: { showingFilters = true },
            onClearAllCriteria: clearAllCriteria,
            isSearchFieldFocused: $isSearchFieldFocused
        )
    }

    private var batchActionBar: some View {
        AnimalListBatchActionBar(
            selectedCount: selectedAnimalIDs.count,
            allVisibleAnimalsSelected: allVisibleAnimalsSelected,
            onToggleSelectAllVisible: toggleSelectAllVisible,
            onMove: { showingPasturePicker = true }
        )
    }

    private var allVisibleAnimalsSelected: Bool {
        !filteredAndSortedAnimals.isEmpty
        && selectedAnimalIDs.count == filteredAndSortedAnimals.count
        && Set(filteredAndSortedAnimals.map(\.id)).isSubset(of: selectedAnimalIDs)
    }

    private var currentFilterChips: [AnimalListFilterChip] {
        var chips: [AnimalListFilterChip] = []

        if showRemovedStatuses {
            chips.append(.init(title: "Off-Herd Visible") { showRemovedStatuses = false })
        }

        if showArchivedRecords {
            chips.append(.init(title: "Archived Visible") { showArchivedRecords = false })
        }

        if let sex = filter.sex {
            chips.append(.init(title: sex.label) { filter.sex = nil })
        }

        if let status = filter.status {
            chips.append(.init(title: status.label) { filter.status = nil })
        }

        if let pastureName = viewModel.pastureName(for: filter.pastureID) {
            chips.append(.init(title: pastureName) { filter.pastureID = nil })
        }

        return chips
    }

    private var hasAnyActiveCriteria: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || filter.isActive
        || showRemovedStatuses
        || showArchivedRecords
    }

    private func reload() {
        viewModel.load(using: repository)
    }

    private func toggleSelectAllVisible() {
        let visible = Set(filteredAndSortedAnimals.map(\.id))

        if visible.isSubset(of: selectedAnimalIDs) {
            selectedAnimalIDs.subtract(visible)
        } else {
            selectedAnimalIDs.formUnion(visible)
        }
    }

    private func clearAllCriteria() {
        searchText = ""
        clearAllFilters()
    }

    private func clearAllFilters() {
        filter = AnimalFilter()
        showRemovedStatuses = false
        showArchivedRecords = false
    }

    private func performPrimarySwipeAction(for animal: AnimalSummary) {
        viewModel.performPrimarySwipeAction(
            animalID: animal.id,
            hardDelete: animal.isArchived || hardDeleteOnSwipe,
            using: repository
        )
    }

    private func restoreArchivedRecord(_ animal: AnimalSummary) {
        viewModel.restore(animalID: animal.id, using: repository)
    }
}
