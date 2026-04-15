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

    private var repository: any AnimalRepository {
        dependencies.animalRepository
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
        .navigationDestination(for: UUID.self) { animalID in
            AnimalDetailView(animalID: animalID)
        }
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
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Animal")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomOverlay
        }
        .sheet(isPresented: $showingAdd, onDismiss: reload) {
            AddAnimalView()
        }
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
                viewModel.move(
                    ids: Array(selectedAnimalIDs),
                    toPastureID: pasture.id,
                    using: repository
                )
                selectedAnimalIDs.removeAll()
                batchMode = false
            }
        }
        .onAppear(perform: reload)
        .animation(.snappy, value: batchMode)
        .animation(.snappy, value: selectedAnimalIDs.count)
        .animation(.snappy, value: currentFilterChips.count)
    }

    private func reload() {
        viewModel.load(using: repository)
    }

    private var herdList: some View {
        List(selection: batchMode ? $selectedAnimalIDs : nil) {
            ForEach(groupedAnimals) { section in
                if shouldUseSections {
                    Section(section.title) {
                        sectionRows(section.animals)
                    }
                } else {
                    sectionRows(section.animals)
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
                animalRow(animal)
                    .tag(animal.id)
                    .listRowBackground(batchRowBackground(for: animal))
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                        dimensions.width
                    }
            } else {
                NavigationLink(value: animal.id) {
                    animalRow(animal)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if animal.isArchived || hardDeleteOnSwipe {
                        Button(role: .destructive) {
                            performPrimarySwipeAction(for: animal)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } else {
                        Button {
                            performPrimarySwipeAction(for: animal)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(.orange)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if animal.isArchived {
                        Button {
                            restoreArchivedRecord(animal)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.blue)
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                    dimensions.width
                }
            }
        }
    }

    @ViewBuilder
    private func animalRow(_ animal: AnimalSummary) -> some View {
        AnimalListRowContent(animal: animal)
    }

    @ViewBuilder
    private func batchRowBackground(for animal: AnimalSummary) -> some View {
        if selectedAnimalIDs.contains(animal.id) {
            Color.accentColor.opacity(0.14)
        } else {
            Color.clear
        }
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
        !filteredAndSortedAnimals.isEmpty &&
        selectedAnimalIDs.count == filteredAndSortedAnimals.count &&
        Set(filteredAndSortedAnimals.map(\.id)).isSubset(of: selectedAnimalIDs)
    }

    private func toggleSelectAllVisible() {
        let visible = Set(filteredAndSortedAnimals.map(\.id))

        if visible.isSubset(of: selectedAnimalIDs) {
            selectedAnimalIDs.subtract(visible)
        } else {
            selectedAnimalIDs.formUnion(visible)
        }
    }


    private var currentFilterChips: [AnimalListFilterChip] {
        var chips: [AnimalListFilterChip] = []

        if showRemovedStatuses {
            chips.append(
                AnimalListFilterChip(title: "Off-Herd Visible") {
                    showRemovedStatuses = false
                }
            )
        }

        if showArchivedRecords {
            chips.append(
                AnimalListFilterChip(title: "Archived Visible") {
                    showArchivedRecords = false
                }
            )
        }

        if let sex = filter.sex {
            chips.append(
                AnimalListFilterChip(title: sex.label) {
                    filter.sex = nil
                }
            )
        }

        if let status = filter.status {
            chips.append(
                AnimalListFilterChip(title: status.label) {
                    filter.status = nil
                }
            )
        }

        if let pastureName = viewModel.pastureName(for: filter.pastureID) {
            chips.append(
                AnimalListFilterChip(title: pastureName) {
                    filter.pastureID = nil
                }
            )
        }

        return chips
    }

    private var hasAnyActiveCriteria: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || filter.isActive
        || showRemovedStatuses
        || showArchivedRecords
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

    private var hasHiddenOffHerdAnimals: Bool {
        viewModel.items.contains(where: { $0.status != .active && !$0.isArchived })
    }

    private var hasHiddenArchivedRecords: Bool {
        viewModel.items.contains(where: \.isArchived)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(emptyStateTitle, systemImage: emptyStateSystemImage)
        } description: {
            Text(emptyStateDescription)
        } actions: {
            if viewModel.items.isEmpty {
                Button("Add Animal") {
                    showingAdd = true
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                Button("Add Sample Data") {
                    dependencies.seedSampleDataIfNeeded()
                    reload()
                }
                .buttonStyle(.bordered)
            } else {
                if filter.isActive || showRemovedStatuses || showArchivedRecords {
                    Button("Clear Filters") {
                        clearAllFilters()
                    }
                }

                if !showRemovedStatuses && hasHiddenOffHerdAnimals {
                    Button("Show Inactive") {
                        showRemovedStatuses = true
                    }
                }

                if !showArchivedRecords && hasHiddenArchivedRecords {
                    Button("Show Archived Records") {
                        showArchivedRecords = true
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if viewModel.items.isEmpty {
            return "No Animals Yet"
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No Matches"
        }

        if filter.isActive {
            return "No Animals Match These Filters"
        }

        if !showArchivedRecords && hasHiddenArchivedRecords && !showRemovedStatuses && !hasHiddenOffHerdAnimals {
            return "Archived Records Hidden"
        }

        if !showRemovedStatuses {
            return "No Active Animals"
        }

        if !showArchivedRecords && hasHiddenArchivedRecords {
            return "Archived Records Hidden"
        }

        return "Nothing to Show"
    }

    private var emptyStateDescription: String {
        if viewModel.items.isEmpty {
            return "Add your first animal to start building the herd."
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different search or clear your text."
        }

        if filter.isActive {
            return "Adjust or clear the current filters to see more animals."
        }

        if !showArchivedRecords && hasHiddenArchivedRecords && !showRemovedStatuses && !hasHiddenOffHerdAnimals {
            return "Archived records are currently hidden."
        }

        if !showRemovedStatuses {
            return "Off-herd animals are currently hidden."
        }

        if !showArchivedRecords && hasHiddenArchivedRecords {
            return "Archived records are currently hidden."
        }

        return "Try changing the current filters or sort."
    }

    private var emptyStateSystemImage: String {
        if viewModel.items.isEmpty {
            return "pawprint"
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "magnifyingglass"
        }

        if filter.isActive {
            return "line.3.horizontal.decrease.circle"
        }

        if !showArchivedRecords && hasHiddenArchivedRecords && !showRemovedStatuses && !hasHiddenOffHerdAnimals {
            return "archivebox"
        }

        if !showRemovedStatuses {
            return "person.3.sequence.fill"
        }

        if !showArchivedRecords && hasHiddenArchivedRecords {
            return "archivebox"
        }

        return "tray"
    }

    private struct AnimalSection: Identifiable {
        let id: String
        let title: String
        let animals: [AnimalSummary]
    }

    private var shouldUseSections: Bool {
        switch sortOrder {
        case .sex, .status, .pasture:
            return true
        default:
            return false
        }
    }

    private var groupedAnimals: [AnimalSection] {
        switch sortOrder {
        case .sex:
            let grouped = Dictionary(grouping: filteredAndSortedAnimals) { animal in
                animal.sex.label
            }

            return grouped
                .map { key, value in
                    AnimalSection(
                        id: "sex-\(key)",
                        title: key,
                        animals: value
                    )
                }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        case .status:
            let grouped = Dictionary(grouping: filteredAndSortedAnimals) { animal in
                animal.status.label
            }

            return grouped
                .map { key, value in
                    AnimalSection(
                        id: "status-\(key)",
                        title: key,
                        animals: value
                    )
                }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        case .pasture:
            let grouped = Dictionary(grouping: filteredAndSortedAnimals) { animal in
                pastureSectionTitle(for: animal)
            }

            return grouped
                .map { key, value in
                    AnimalSection(
                        id: "pasture-\(key)",
                        title: key,
                        animals: value
                    )
                }
                .sorted { lhs, rhs in
                    pastureSectionSortKey(for: lhs.title) < pastureSectionSortKey(for: rhs.title)
                }

        default:
            return [
                AnimalSection(
                    id: "all",
                    title: "Animals",
                    animals: filteredAndSortedAnimals
                )
            ]
        }
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

    private var filteredAndSortedAnimals: [AnimalSummary] {
        var result = viewModel.items

        if !showRemovedStatuses {
            result = result.filter { $0.status == .active }
        }

        if !showArchivedRecords {
            result = result.filter { !$0.isArchived }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter {
                $0.displayTagNumber.localizedCaseInsensitiveContains(query)
                || tagColorLibrary.formattedTag(tagNumber: $0.displayTagNumber, colorID: $0.displayTagColorID).localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
            }
        }

        if let selectedSex = filter.sex {
            result = result.filter { $0.sex == selectedSex }
        }

        if let selectedStatus = filter.status {
            result = result.filter { $0.status == selectedStatus }
        }

        if let selectedPastureID = filter.pastureID {
            result = result.filter { $0.pastureID == selectedPastureID }
        }

        switch sortOrder {
        case .tagAscending:
            result.sort { $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber) == .orderedAscending }
        case .tagDescending:
            result.sort { $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber) == .orderedDescending }
        case .birthDateNewest:
            result.sort { $0.birthDate > $1.birthDate }
        case .birthDateOldest:
            result.sort { $0.birthDate < $1.birthDate }
        case .sex:
            result.sort { lhs, rhs in
                if lhs.sex.rawValue != rhs.sex.rawValue {
                    return lhs.sex.rawValue < rhs.sex.rawValue
                }

                return lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
            }
        case .status:
            result.sort { lhs, rhs in
                if lhs.status.rawValue != rhs.status.rawValue {
                    return lhs.status.rawValue < rhs.status.rawValue
                }

                return lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
            }
        case .pasture:
            result.sort { lhs, rhs in
                let lhsKey = pastureSortKey(for: lhs)
                let rhsKey = pastureSortKey(for: rhs)

                if lhsKey != rhsKey {
                    return lhsKey < rhsKey
                }

                return lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
            }
        }

        return result
    }

    private func pastureSectionTitle(for animal: AnimalSummary) -> String {
        if animal.location == .workingPen {
            return "Working Pen"
        }

        if let pastureName = animal.pastureName, !pastureName.isEmpty {
            return pastureName
        }

        return "No Pasture"
    }

    private func pastureSectionSortKey(for title: String) -> String {
        switch title {
        case "Working Pen":
            return "0-working-pen"
        case "No Pasture":
            return "2-no-pasture"
        default:
            return "1-\(title.lowercased())"
        }
    }

    private func pastureSortKey(for animal: AnimalSummary) -> String {
        pastureSectionSortKey(for: pastureSectionTitle(for: animal))
    }
}
