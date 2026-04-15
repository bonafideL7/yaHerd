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

    private var backgroundView: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
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
        let def = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)

        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                AnimalTagView(
                    tagNumber: animal.displayTagNumber,
                    color: def.color,
                    colorName: def.name
                )

                if !animal.name.isEmpty {
                    infoPill(
                        title:animal.name,
                        systemImage: ""
                    )
                } else {
                    infoPill(
                        title: animal.sex.label,
                        systemImage: ""
                    )
                }
            }
            VStack(alignment: .trailing, spacing: 8) {
                if animal.status != .active || animal.isArchived {
                    statusPills(for: animal)
                } else {
                    locationBadges(for: animal)
                }
                HStack {
                    infoPill(title: animal.age, systemImage: "clock")
                    infoPill(
                        title: animal.birthDate.formatted(
                            .dateTime
                                .year(.twoDigits)
                                .month(.twoDigits)
                                .day(.twoDigits)
                        ),
                        systemImage: "calendar"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func infoPill(
        title: String,
        systemImage: String,
        tint: Color = .accentColor
    ) -> some View {
        HStack(spacing: 3) {
            if !systemImage.isEmpty {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.callout)
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
    }

    @ViewBuilder
    private func statusPills(for animal: AnimalSummary) -> some View {
        HStack(spacing: 6) {
            if animal.status != .active {
                infoPill(
                    title: animal.status.label,
                    systemImage: animal.status.systemImage,
                    tint: .secondary
                )
            }

            if animal.isArchived {
                infoPill(
                    title: "Archived",
                    systemImage: "archivebox",
                    tint: .orange
                )
            }
        }
    }

    @ViewBuilder
    private func locationBadges(for animal: AnimalSummary) -> some View {
        if animal.location == .workingPen {
            pastureBadge(
                "Working Pen",
                systemImage: "figure.corral",
                tint: .orange,
                fillOpacity: 0.14
            )
        } else if let pastureName = animal.pastureName {
            pastureBadge(
                pastureName,
                systemImage: "leaf",
                tint: .accent,
                fillOpacity: 0.12
            )
        } else {
            Spacer()
        }
    }

    @ViewBuilder
    private func pastureBadge(
        _ title: String,
        systemImage: String,
        tint: Color,
        fillOpacity: Double
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(
            Capsule()
                .fill(tint.opacity(fillOpacity))
        )
    }

    @ViewBuilder
    private func batchRowBackground(for animal: AnimalSummary) -> some View {
        if selectedAnimalIDs.contains(animal.id) {
            Color.accentColor.opacity(0.14)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if isSearching {
                    bottomSearchField

                    Button("Cancel") {
                        searchText = ""
                        isSearchFieldFocused = false
                        withAnimation(.snappy) {
                            isSearching = false
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .buttonStyle(.plain)
                } else {
                    Menu {
                        Picker("Sort", selection: $sortOrder) {
                            ForEach(AnimalSortOrder.allCases, id: \.self) { option in
                                Label(option.label, systemImage: option.icon)
                                    .tag(option)
                            }
                        }
                    } label: {
                        floatingControlLabel(
                            title: sortOrder.label,
                            systemImage: "arrow.up.arrow.down"
                        )
                    }

                    Button {
                        showingFilters = true
                    } label: {
                        floatingControlLabel(
                            title: filter.isActive || showRemovedStatuses || showArchivedRecords ? "Filters On" : "Filters",
                            systemImage: (filter.isActive || showRemovedStatuses || showArchivedRecords)
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.snappy) {
                            isSearching = true
                        }
                    } label: {
                        floatingIconControlLabel(systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.plain)
                }
            }

            if !isSearching && !currentFilterChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if hasAnyActiveCriteria {
                            Button("Clear") {
                                clearAllCriteria()
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.thinMaterial, in: Capsule())
                            .buttonStyle(.plain)
                        }
                        if !currentFilterChips.isEmpty {
                            Text("\(currentFilterChips.count) active filter\(currentFilterChips.count == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 4)
                        }

                        ForEach(currentFilterChips) { chip in
                            Button {
                                chip.remove()
                            } label: {
                                HStack(spacing: 6) {
                                    Text(chip.title)
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                }
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .shadow(radius: 10, y: 4)
        .onChange(of: isSearching) { _, newValue in
            if newValue {
                isSearchFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private func floatingIconControlLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.medium))
            .frame(width: 44, height: 44)
            .background(.thinMaterial, in: Capsule())
    }

    @ViewBuilder
    private func floatingControlLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: Capsule())
    }

    private var bottomSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search tag, color, or name", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .focused($isSearchFieldFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: Capsule())
    }

    private var batchActionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(selectedAnimalIDs.isEmpty ? "Selection Mode" : "\(selectedAnimalIDs.count) Selected")
                    .font(.caption)

                Button(allVisibleAnimalsSelected ? "Deselect All" : "Select All") {
                    toggleSelectAllVisible()
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.automatic)
            }

            Spacer()

            Button {
                showingPasturePicker = true
            } label: {
                Label("Move", systemImage: "arrowshape.turn.up.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedAnimalIDs.isEmpty)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .shadow(radius: 10, y: 4)
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

    private struct FilterChip: Identifiable {
        let id = UUID()
        let title: String
        let remove: () -> Void
    }

    private var currentFilterChips: [FilterChip] {
        var chips: [FilterChip] = []

        if showRemovedStatuses {
            chips.append(
                FilterChip(title: "Off-Herd Visible") {
                    showRemovedStatuses = false
                }
            )
        }

        if showArchivedRecords {
            chips.append(
                FilterChip(title: "Archived Visible") {
                    showArchivedRecords = false
                }
            )
        }

        if let sex = filter.sex {
            chips.append(
                FilterChip(title: sex.label) {
                    filter.sex = nil
                }
            )
        }

        if let status = filter.status {
            chips.append(
                FilterChip(title: status.label) {
                    filter.status = nil
                }
            )
        }

        if let pastureName = viewModel.pastureName(for: filter.pastureID) {
            chips.append(
                FilterChip(title: pastureName) {
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
