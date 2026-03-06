//
//  AnimalListView.swift
//

import SwiftUI
import SwiftData

struct AnimalListView: View {
    
    // MARK: Environment
    
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Query private var animals: [Animal]
    
    // MARK: Storage
    
    @AppStorage("allowHardDelete") private var allowHardDelete = false
    
    // MARK: State
    
    @State private var searchText = ""
    @State private var sortOrder: AnimalSortOrder = .tagAscending
    @State private var showingAdd = false
    @State private var showingFilters = false
    @State private var filter = AnimalFilter()
    @State private var showArchived = false
    
    @State private var batchMode = false
    @State private var selectedAnimals: Set<Animal> = []
    @State private var showingBatchMoveSheet = false
    
    // MARK: View
    
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
        .navigationDestination(for: Animal.self) { animal in
            AnimalDetailView(animal: animal)
        }
//        .searchable(
//            text: $searchText,
//            placement: .navigationBarDrawer(displayMode: .automatic),
//            prompt: "Search tag or color"
//        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(batchMode ? "Done" : "Select") {
                    withAnimation(.snappy) {
                        batchMode.toggle()
                        if !batchMode {
                            selectedAnimals.removeAll()
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
        .sheet(isPresented: $showingAdd) {
            AddAnimalView()
        }
        .sheet(isPresented: $showingFilters) {
            AnimalFilterView(filter: $filter)
        }
        .sheet(isPresented: $showingBatchMoveSheet) {
            BatchMoveSheet(
                animals: Array(selectedAnimals),
                onComplete: {
                    selectedAnimals.removeAll()
                    batchMode = false
                }
            )
        }
        .animation(.snappy, value: batchMode)
        .animation(.snappy, value: selectedAnimals.count)
        .animation(.snappy, value: currentFilterChips.count)
    }
    
    // MARK: Main List
    
    private var herdList: some View {
        List(selection: batchMode ? $selectedAnimals : .constant(Set<Animal>())) {
            if !currentFilterChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    activeFilterChips
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }
            
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
    private func sectionRows(_ animals: [Animal]) -> some View {
        ForEach(animals) { animal in
            if batchMode {
                animalRow(animal)
                    .tag(animal)
                    .listRowBackground(batchRowBackground(for: animal))
            } else {
                NavigationLink(value: animal) {
                    animalRow(animal)
                }
            }
        }
        .onDelete { offsets in
            deleteAnimals(at: offsets, in: animals)
        }
    }
    
    // MARK: Row
    
    @ViewBuilder
    private func animalRow(_ animal: Animal) -> some View {
        let def = tagColorLibrary.resolvedDefinition(for: animal)
        
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(def.color.opacity(0.18))
                    .frame(width: 38, height: 38)
                
                TagColorTagIcon(
                    color: def.color,
                    accessibilityLabel: "Tag color: \(def.name)"
                )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(animal.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(animal.tagNumber)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 8) {
                    infoPill(
                        title: (animal.sex ?? .female).label,
                        systemImage: "pawprint"
                    )
                    
                    if animal.location == .workingPen {
                        infoPill(
                            title: "Working Pen",
                            systemImage: "figure.corral",
                            tint: .orange
                        )
                    } else if let pasture = animal.pasture {
                        infoPill(
                            title: pasture.name,
                            systemImage: "leaf"
                        )
                    }
                }
            }
            
            Spacer(minLength: 8)
            
            if batchMode {
                Image(systemName: selectedAnimals.contains(animal) ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(selectedAnimals.contains(animal) ? Color.accentColor : .tertiary)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private func infoPill(
        title: String,
        systemImage: String,
        tint: Color = .secondary
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
    }
    
    @ViewBuilder
    private func batchRowBackground(for animal: Animal) -> some View {
        if selectedAnimals.contains(animal) {
            Color.accentColor.opacity(0.14)
        } else {
            Color.clear
        }
    }
    
    // MARK: Bottom Overlay
    
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
    
    //MARK: Floating Controller
    
    private var floatingControlBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !currentFilterChips.isEmpty {
                Text("\(currentFilterChips.count) active filter\(currentFilterChips.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            
            HStack(spacing: 10) {
                bottomSearchField
                
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
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
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
                            title: filter.isActive ? "Filters On" : "Filters",
                            systemImage: filter.isActive
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        showArchived.toggle()
                    } label: {
                        floatingControlLabel(
                            title: showArchived ? "Archived" : "Alive",
                            systemImage: showArchived ? "archivebox.fill" : "heart.text.square.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if !currentFilterChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
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
        .background(.thinMaterial, in: Capsule())
    }
    
    private var batchActionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedAnimals.isEmpty ? "Selection Mode" : "\(selectedAnimals.count) Selected")
                    .font(.headline)
                
                Text(selectedAnimals.isEmpty ? "Tap rows to select animals" : "Batch actions are ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                showingBatchMoveSheet = true
            } label: {
                Label("Move", systemImage: "arrowshape.turn.up.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedAnimals.isEmpty)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .shadow(radius: 10, y: 4)
    }
    
    // MARK: Filter Chips
    
    @ViewBuilder
    private var activeFilterChips: some View {
        let chips = currentFilterChips
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
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
                
                Button("Clear All") {
                    clearAllFilters()
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .buttonStyle(.plain)
            }
        }
    }
    
    private struct FilterChip: Identifiable {
        let id = UUID()
        let title: String
        let remove: () -> Void
    }
    
    private var currentFilterChips: [FilterChip] {
        var chips: [FilterChip] = []
        
        if showArchived {
            chips.append(
                FilterChip(title: "Archived Visible") {
                    showArchived = false
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
                FilterChip(title: String(describing: status)) {
                    filter.status = nil
                }
            )
        }
        
        if let pasture = filter.pasture {
            chips.append(
                FilterChip(title: pasture.name) {
                    filter.pasture = nil
                }
            )
        }
        
        return chips
    }
    
    private var hasAnyActiveCriteria: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || filter.isActive
        || showArchived
    }
    
    private func clearAllCriteria() {
        searchText = ""
        clearAllFilters()
    }
    
    private func clearAllFilters() {
        filter = AnimalFilter()
        showArchived = false
    }
    
    // MARK: Empty State
    
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(emptyStateTitle, systemImage: emptyStateSystemImage)
        } description: {
            Text(emptyStateDescription)
        } actions: {
            if animals.isEmpty {
                Button("Add Animal") {
                    showingAdd = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                if filter.isActive || showArchived {
                    Button("Clear Filters") {
                        clearAllFilters()
                    }
                }
                
                if !showArchived && animals.contains(where: { $0.status != .alive }) {
                    Button("Show Archived") {
                        showArchived = true
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateTitle: String {
        if animals.isEmpty {
            return "No Animals Yet"
        }
        
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No Matches"
        }
        
        if filter.isActive {
            return "No Animals Match These Filters"
        }
        
        if !showArchived {
            return "No Active Animals"
        }
        
        return "Nothing to Show"
    }
    
    private var emptyStateDescription: String {
        if animals.isEmpty {
            return "Add your first animal to start building the herd."
        }
        
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different search or clear your text."
        }
        
        if filter.isActive {
            return "Adjust or clear the current filters to see more animals."
        }
        
        if !showArchived {
            return "Archived animals are currently hidden."
        }
        
        return "Try changing the current filters or sort."
    }
    
    private var emptyStateSystemImage: String {
        if animals.isEmpty {
            return "pawprint"
        }
        
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "magnifyingglass"
        }
        
        if filter.isActive {
            return "line.3.horizontal.decrease.circle"
        }
        
        if !showArchived {
            return "archivebox"
        }
        
        return "tray"
    }
    
    // MARK: Sections
    
    private struct AnimalSection: Identifiable {
        let id: String
        let title: String
        let animals: [Animal]
    }
    
    private var shouldUseSections: Bool {
        switch sortOrder {
        case .sex, .status:
            return true
        default:
            return false
        }
    }
    
    private var groupedAnimals: [AnimalSection] {
        switch sortOrder {
        case .sex:
            let grouped = Dictionary(grouping: filteredAndSortedAnimals) { animal in
                (animal.sex ?? .female).label
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
                String(describing: animal.status)
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
    
    // MARK: Delete Animal
    
    private func deleteAnimals(at offsets: IndexSet, in source: [Animal]) {
        for index in offsets {
            let animal = source[index]
            
            if allowHardDelete {
                context.delete(animal)
            } else {
                animal.status = .deceased
            }
        }
        
        try? context.save()
    }
    
    // MARK: Filter + Sort Logic
    
    private var filteredAndSortedAnimals: [Animal] {
        var result = animals
        
        if !showArchived {
            result = result.filter { $0.status == .alive }
        }
        
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter {
                $0.tagNumber.localizedCaseInsensitiveContains(query)
                || tagColorLibrary.formattedTag(for: $0).localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
            }
        }
        
        if let selectedSex = filter.sex {
            result = result.filter { $0.sex == selectedSex }
        }
        
        if let selectedStatus = filter.status {
            result = result.filter { $0.status == selectedStatus }
        }
        
        if let selectedPasture = filter.pasture {
            result = result.filter { $0.pasture == selectedPasture }
        }
        
        switch sortOrder {
        case .tagAscending:
            result.sort { $0.tagNumber.localizedStandardCompare($1.tagNumber) == .orderedAscending }
        case .tagDescending:
            result.sort { $0.tagNumber.localizedStandardCompare($1.tagNumber) == .orderedDescending }
        case .birthDateNewest:
            result.sort { $0.birthDate > $1.birthDate }
        case .birthDateOldest:
            result.sort { $0.birthDate < $1.birthDate }
        case .sex:
            result.sort { ($0.sex?.rawValue ?? "") < ($1.sex?.rawValue ?? "") }
        case .status:
            result.sort { $0.status.rawValue < $1.status.rawValue }
        }
        
        return result
    }
}
