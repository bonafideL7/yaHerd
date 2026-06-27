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
    @State private var internalSearchText = ""
    @State private var sortOrder: AnimalSortOrder = .tagAscending
    @State private var showingFilters = false
    @State private var filter = AnimalFilter()
    @State private var showRemovedStatuses = false
    @State private var showArchivedRecords = false
    @State private var internalIsSearching = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var batchMode = false
    @State private var selectedAnimalIDs: Set<UUID> = []
    @State private var collapsedSectionIDs: Set<String> = []
    @State private var showingPasturePicker = false
    @State private var inlineEntry = AnimalInlineEntryViewModel()
    @State private var isShowingInlineSexPicker = false
    @State private var isShowingInlinePasturePicker = false
    @State private var isShowingInlineBirthDateOptions = false
    @State private var isShowingInlineBirthDatePicker = false
    @State private var ignoresNextInlineFocusLoss = false
    @State private var detailAnimalID: UUID?
    @State private var isShowingInlineDetail = false
    private let externalSearchText: Binding<String>?
    private let externalIsSearching: Binding<Bool>?
    private let externalSortOrder: Binding<AnimalSortOrder>?
    private let externalFilter: Binding<AnimalFilter>?
    private let externalShowRemovedStatuses: Binding<Bool>?
    private let externalShowArchivedRecords: Binding<Bool>?
    private let externalShowingFilters: Binding<Bool>?
    private let showsSearchControls: Bool
    private let usesExternalSearchField: Bool
    private let hidesControlsUntilSearch: Bool
    private let usesShellBottomAccessory: Bool
    private let onOpenSettings: () -> Void

    init(
        searchText: Binding<String>? = nil,
        isSearching: Binding<Bool>? = nil,
        sortOrder: Binding<AnimalSortOrder>? = nil,
        filter: Binding<AnimalFilter>? = nil,
        showRemovedStatuses: Binding<Bool>? = nil,
        showArchivedRecords: Binding<Bool>? = nil,
        showingFilters: Binding<Bool>? = nil,
        usesExternalSearchField: Bool = false,
        hidesControlsUntilSearch: Bool = false,
        showsSearchControls: Bool = false,
        usesShellBottomAccessory: Bool = false,
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.externalSearchText = searchText
        self.externalIsSearching = isSearching
        self.externalSortOrder = sortOrder
        self.externalFilter = filter
        self.externalShowRemovedStatuses = showRemovedStatuses
        self.externalShowArchivedRecords = showArchivedRecords
        self.externalShowingFilters = showingFilters
        self.usesExternalSearchField = usesExternalSearchField
        self.hidesControlsUntilSearch = hidesControlsUntilSearch
        self.showsSearchControls = showsSearchControls
        self.usesShellBottomAccessory = usesShellBottomAccessory
        self.onOpenSettings = onOpenSettings
    }

    private var searchTextBinding: Binding<String> {
        Binding {
            externalSearchText?.wrappedValue ?? internalSearchText
        } set: { newValue in
            if let externalSearchText {
                externalSearchText.wrappedValue = newValue
            } else {
                internalSearchText = newValue
            }
        }
    }

    private var isSearchingBinding: Binding<Bool> {
        Binding {
            externalIsSearching?.wrappedValue ?? internalIsSearching
        } set: { newValue in
            if let externalIsSearching {
                externalIsSearching.wrappedValue = newValue
            } else {
                internalIsSearching = newValue
            }
        }
    }

    private var sortOrderBinding: Binding<AnimalSortOrder> {
        Binding {
            externalSortOrder?.wrappedValue ?? sortOrder
        } set: { newValue in
            if let externalSortOrder {
                externalSortOrder.wrappedValue = newValue
            } else {
                sortOrder = newValue
            }
        }
    }

    private var filterBinding: Binding<AnimalFilter> {
        Binding {
            externalFilter?.wrappedValue ?? filter
        } set: { newValue in
            if let externalFilter {
                externalFilter.wrappedValue = newValue
            } else {
                filter = newValue
            }
        }
    }

    private var showRemovedStatusesBinding: Binding<Bool> {
        Binding {
            externalShowRemovedStatuses?.wrappedValue ?? showRemovedStatuses
        } set: { newValue in
            if let externalShowRemovedStatuses {
                externalShowRemovedStatuses.wrappedValue = newValue
            } else {
                showRemovedStatuses = newValue
            }
        }
    }

    private var showArchivedRecordsBinding: Binding<Bool> {
        Binding {
            externalShowArchivedRecords?.wrappedValue ?? showArchivedRecords
        } set: { newValue in
            if let externalShowArchivedRecords {
                externalShowArchivedRecords.wrappedValue = newValue
            } else {
                showArchivedRecords = newValue
            }
        }
    }

    private var showingFiltersBinding: Binding<Bool> {
        Binding {
            externalShowingFilters?.wrappedValue ?? showingFilters
        } set: { newValue in
            if let externalShowingFilters {
                externalShowingFilters.wrappedValue = newValue
            } else {
                showingFilters = newValue
            }
        }
    }

    private var searchTextValue: String {
        searchTextBinding.wrappedValue
    }

    private var isSearchModeActive: Bool {
        isSearchingBinding.wrappedValue
    }

    private var sortOrderValue: AnimalSortOrder {
        sortOrderBinding.wrappedValue
    }

    private var filterValue: AnimalFilter {
        filterBinding.wrappedValue
    }

    private var showRemovedStatusesValue: Bool {
        showRemovedStatusesBinding.wrappedValue
    }

    private var showArchivedRecordsValue: Bool {
        showArchivedRecordsBinding.wrappedValue
    }

    private var filtersAreActive: Bool {
        filterValue.isActive || showRemovedStatusesValue || showArchivedRecordsValue
    }

    private var repository: any AnimalRepository { dependencies.animalRepository }

    private var filteredAndSortedAnimals: [AnimalSummary] {
        AnimalListDerivations.filteredAndSortedAnimals(
            items: viewModel.items,
            searchText: searchTextValue,
            sortOrder: sortOrderValue,
            filter: filterValue,
            showRemovedStatuses: showRemovedStatusesValue,
            showArchivedRecords: showArchivedRecordsValue
        ) { tagNumber, colorID in
            tagColorLibrary.formattedTag(tagNumber: tagNumber, colorID: colorID)
        }
    }

    private var groupedAnimals: [AnimalSection] {
        AnimalListDerivations.groupedAnimals(filteredAndSortedAnimals, sortOrder: sortOrderValue)
    }

    private var shouldUseSections: Bool {
        AnimalListDerivations.shouldUseSections(for: sortOrderValue)
    }

    private var currentSectionIDs: Set<String> {
        guard shouldUseSections else { return [] }
        return Set(groupedAnimals.map(\.id))
    }

    private var canCollapseSections: Bool {
        shouldUseSections && !groupedAnimals.isEmpty
    }

    private var emptyStateConfiguration: AnimalListEmptyStateConfiguration {
        AnimalListDerivations.emptyStateConfiguration(
            items: viewModel.items,
            searchText: searchTextValue,
            filter: filterValue,
            showRemovedStatuses: showRemovedStatusesValue,
            showArchivedRecords: showArchivedRecordsValue
        )
    }

    private var hasHiddenOffHerdAnimals: Bool {
        AnimalListDerivations.hasHiddenOffHerdAnimals(items: viewModel.items)
    }

    private var hasHiddenArchivedRecords: Bool {
        AnimalListDerivations.hasHiddenArchivedRecords(items: viewModel.items)
    }

    private var inlineHelperText: String {
        "Enter color prefix + number, like W345 for white 345 or LB01 for light blue 01. Unrecognized prefixes are saved as the animal name."
    }

    private var errorMessageIsPresented: Binding<Bool> {
        Binding {
            viewModel.errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                viewModel.errorMessage = nil
            }
        }
    }

    var body: some View {
        Group {
            if filteredAndSortedAnimals.isEmpty && !inlineEntry.isActive {
                emptyStateView
            } else {
                herdList
            }
        }
        .navigationDestination(for: UUID.self) { AnimalDetailView(animalID: $0) }
        .navigationDestination(isPresented: $isShowingInlineDetail) {
            if let detailAnimalID {
                AnimalDetailView(animalID: detailAnimalID)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                sortToolbarAuxiliaryButton
                animalToolbarAction
            }

        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomOverlay }
        .overlay(alignment: .bottomTrailing) {
            if !batchMode && !inlineEntry.isActive {
                addAnimalButton
                    .padding(.trailing, 24)
                    .padding(.bottom, floatingAddButtonBottomPadding)
            }
        }
        .sheet(isPresented: showingFiltersBinding) {
            AnimalFilterView(
                filter: filterBinding,
                showRemovedStatuses: showRemovedStatusesBinding,
                showArchivedRecords: showArchivedRecordsBinding,
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
        .confirmationDialog("Sex", isPresented: $isShowingInlineSexPicker, titleVisibility: .visible) {
            ForEach(Sex.allCases, id: \.self) { option in
                Button(option.label) {
                    inlineEntry.sex = option
                    requestInlineEntryFocus()
                }
            }
        }
        .confirmationDialog("Pasture", isPresented: $isShowingInlinePasturePicker, titleVisibility: .visible) {
            Button("No Pasture") {
                inlineEntry.pastureID = nil
                requestInlineEntryFocus()
            }

            ForEach(viewModel.pastureOptions) { pasture in
                Button(pasture.name) {
                    inlineEntry.pastureID = pasture.id
                    requestInlineEntryFocus()
                }
            }
        }
        .confirmationDialog("Birthdate", isPresented: $isShowingInlineBirthDateOptions, titleVisibility: .visible) {
            Button("Today") {
                inlineEntry.birthDate = Calendar.current.startOfDay(for: .now)
                requestInlineEntryFocus()
            }

            Button("Yesterday") {
                inlineEntry.birthDate = Calendar.current.date(
                    byAdding: .day,
                    value: -1,
                    to: Calendar.current.startOfDay(for: .now)
                ) ?? .now
                requestInlineEntryFocus()
            }

            Button("Choose Date…") {
                inlineEntry.ignoresNextFocusLoss = true
                isShowingInlineBirthDatePicker = true
            }
        }
        .sheet(isPresented: $isShowingInlineBirthDatePicker) {
            inlineBirthDatePickerSheet
        }
        .alert("Animal Not Saved", isPresented: errorMessageIsPresented) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear(perform: reload)
        .scrollDismissesKeyboard(.interactively)
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
            collapsedSectionIDs: $collapsedSectionIDs,
            inlineEntryIsActive: inlineEntry.isActive,
            inlineEntryIdentity: inlineEntry.identity,
            editingAnimalID: inlineEntry.editingAnimalID,
            inlineText: $inlineEntry.text,
            inlineSex: $inlineEntry.sex,
            inlineBirthDate: $inlineEntry.birthDate,
            inlinePastureID: $inlineEntry.pastureID,
            pastureOptions: viewModel.pastureOptions,
            inlineHelperText: inlineHelperText,
            inlineFocusRequestID: inlineEntry.focusRequestID,
            onStartNewInlineEntry: beginNewInlineEntry,
            onStartEditingAnimal: beginInlineEditing,
            onSubmitInlineEntry: submitInlineEntry,
            onCommitInlineEntryFocusLoss: commitInlineEntryFromFocusLoss,
            onCancelInlineEntry: cancelInlineEntry,
            onOpenInlineDetails: openInlineDetails,
            onPrimarySwipeAction: performPrimarySwipeAction,
            onRestoreArchivedRecord: restoreArchivedRecord
        )
    }

    private var addAnimalButton: some View {
        Button {
            beginNewInlineEntry()
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.accentColor))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        }
        .accessibilityLabel("Add Animal")
    }

    @ViewBuilder
    private var sortToolbarAuxiliaryButton: some View {
        if sortOrderValue.canReverseDirection && !batchMode {
            Button {
                reverseSortDirection()
            } label: {
                Image(systemName: sortOrderValue.reverseDirectionIcon)
                    .font(.system(size: 17, weight: .semibold))
            }
            .accessibilityLabel(sortOrderValue.reverseDirectionAccessibilityLabel)
            .accessibilityHint("Reverses the current animal sort direction")
        } else if canCollapseSections && !batchMode {
            Button {
                collapseAllSections()
            } label: {
                Image(systemName: "rectangle.compress.vertical")
                    .font(.system(size: 17, weight: .semibold))
            }
            .accessibilityLabel("Collapse All Sections")
            .accessibilityHint("Collapses every visible animal group")
        }
    }

    @ViewBuilder
    private var animalToolbarAction: some View {
        if batchMode {
            Button {
                toggleBatchMode()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Done Selecting")
        } else {
            Menu {
                Button {
                    toggleBatchMode()
                } label: {
                    Label("Select Animals", systemImage: "checklist")
                }

                Divider()

                NavigationLink {
                    FieldChecksView(mode: .all)
                } label: {
                    Label("Pasture Checks", systemImage: "checklist")
                }

                NavigationLink {
                    WorkingSessionsView()
                } label: {
                    Label("Working Sessions", systemImage: "wrench.and.screwdriver")
                }

                Divider()

                Button {
                    onOpenSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                toolbarMenuLabel
            }
            .accessibilityLabel("Animal list actions")
        }
    }

    private var toolbarMenuLabel: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
    }

    private var floatingAddButtonBottomPadding: CGFloat {
        shouldShowFloatingControlBar ? 106 : 24
    }

    private var emptyStateView: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: beginNewInlineEntry)

            AnimalListEmptyStateView(
                configuration: emptyStateConfiguration,
                hasItems: !viewModel.items.isEmpty,
                filtersAreActive: filtersAreActive,
                hasHiddenOffHerdAnimals: hasHiddenOffHerdAnimals,
                hasHiddenArchivedRecords: hasHiddenArchivedRecords,
                showRemovedStatuses: showRemovedStatusesValue,
                showArchivedRecords: showArchivedRecordsValue,
                colorScheme: colorScheme,
                onAddAnimal: beginNewInlineEntry,
                onAddSampleData: {
                    dependencies.seedSampleDataIfNeeded()
                    reload()
                },
                onAddLargeSampleData: {
                    dependencies.seedLargeSampleDataIfNeeded()
                    reload()
                },
                onClearFilters: clearAllFilters,
                onShowInactive: { showRemovedStatusesBinding.wrappedValue = true },
                onShowArchivedRecords: { showArchivedRecordsBinding.wrappedValue = true }
            )
        }
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        if inlineEntry.isActive {
            VStack(spacing: 10) {
                inlineEntryAccessoryBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        } else if batchMode {
            VStack(spacing: 10) {
                batchActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        } else if shouldShowFloatingControlBar {
            VStack(spacing: 10) {
                floatingControlBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        } else {
            Color.clear
                .frame(height: 88)
                .allowsHitTesting(false)
        }
    }

    private var inlineEntryAccessoryBar: some View {
        HStack(spacing: 12) {
            inlineAccessoryButton(
                systemName: "figure.stand",
                accessibilityLabel: "Sex",
                accessibilityValue: inlineEntry.sex.label
            ) {
                presentInlineEntryPicker { isShowingInlineSexPicker = true }
            }

            inlineAccessoryButton(
                systemName: "leaf",
                accessibilityLabel: "Pasture",
                accessibilityValue: selectedInlinePastureLabel
            ) {
                presentInlineEntryPicker { isShowingInlinePasturePicker = true }
            }

            inlineAccessoryButton(
                systemName: "calendar",
                accessibilityLabel: "Birthdate",
                accessibilityValue: inlineEntry.birthDate.formatted(date: .abbreviated, time: .omitted)
            ) {
                presentInlineEntryPicker { isShowingInlineBirthDateOptions = true }
            }

            Spacer(minLength: 12)

            Button(action: submitInlineEntry) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 40)
                    .contentShape(Rectangle())
            }
            .disabled(inlineEntry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(inlineEntry.editingAnimalID == nil ? "Add animal" : "Save animal")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar, in: Capsule())
    }

    private var selectedInlinePastureLabel: String {
        guard let pastureID = inlineEntry.pastureID else { return "No Pasture" }
        return viewModel.pastureOptions.first(where: { $0.id == pastureID })?.name ?? "Pasture"
    }

    private func inlineAccessoryButton(
        systemName: String,
        accessibilityLabel: String,
        accessibilityValue: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3)
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var inlineBirthDatePickerSheet: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Birthdate",
                    selection: $inlineEntry.birthDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
            }
            .navigationTitle("Birthdate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    ToolbarDoneButton {
                        isShowingInlineBirthDatePicker = false
                        requestInlineEntryFocus()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear {
            requestInlineEntryFocus()
        }
    }

    private var shouldShowFloatingControlBar: Bool {
        !usesShellBottomAccessory && (!hidesControlsUntilSearch || isSearchModeActive || hasAnyActiveCriteria)
    }

    private var floatingControlBar: some View {
        AnimalListFloatingControlBar(
            isSearching: isSearchingBinding,
            searchText: searchTextBinding,
            sortOrder: sortOrderBinding,
            filtersAreActive: filtersAreActive,
            filterChipCount: currentFilterChips.count,
            hasAnyActiveCriteria: hasAnyActiveCriteria,
            chips: currentFilterChips,
            showsSearchControl: showsSearchControls,
            usesExternalSearchField: usesExternalSearchField,
            onShowFilters: { showingFiltersBinding.wrappedValue = true },
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

        if showRemovedStatusesValue {
            chips.append(.init(title: "Off-Herd Visible") { showRemovedStatusesBinding.wrappedValue = false })
        }

        if showArchivedRecordsValue {
            chips.append(.init(title: "Archived Visible") { showArchivedRecordsBinding.wrappedValue = false })
        }

        if let sex = filterValue.sex {
            chips.append(.init(title: sex.label) {
                var updatedFilter = filterValue
                updatedFilter.sex = nil
                filterBinding.wrappedValue = updatedFilter
            })
        }

        if let animalType = filterValue.animalType {
            chips.append(.init(title: animalType.label) {
                var updatedFilter = filterValue
                updatedFilter.animalType = nil
                filterBinding.wrappedValue = updatedFilter
            })
        }

        if let status = filterValue.status {
            chips.append(.init(title: status.label) {
                var updatedFilter = filterValue
                updatedFilter.status = nil
                filterBinding.wrappedValue = updatedFilter
            })
        }

        switch filterValue.pasture {
        case .any:
            break
        case .noPasture:
            chips.append(.init(title: "No Pasture") {
                var updatedFilter = filterValue
                updatedFilter.pasture = .any
                filterBinding.wrappedValue = updatedFilter
            })
        case let .pasture(pastureID):
            if let pastureName = viewModel.pastureName(for: pastureID) {
                chips.append(.init(title: pastureName) {
                    var updatedFilter = filterValue
                    updatedFilter.pasture = .any
                    filterBinding.wrappedValue = updatedFilter
                })
            }
        }

        if filterValue.location.isActive {
            chips.append(.init(title: filterValue.location.label) {
                var updatedFilter = filterValue
                updatedFilter.location = .any
                filterBinding.wrappedValue = updatedFilter
            })
        }


        if filterValue.recordIssue.isActive {
            chips.append(.init(title: filterValue.recordIssue.label) {
                var updatedFilter = filterValue
                updatedFilter.recordIssue = .any
                filterBinding.wrappedValue = updatedFilter
            })
        }

        return chips
    }

    private var hasAnyActiveCriteria: Bool {
        !searchTextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || filterValue.isActive
        || showRemovedStatusesValue
        || showArchivedRecordsValue
    }

    private func reload() {
        viewModel.load(using: repository)
    }

    private func toggleBatchMode() {
        withAnimation(.snappy) {
            batchMode.toggle()
            if !batchMode {
                selectedAnimalIDs.removeAll()
            }
        }
    }

    private func reverseSortDirection() {
        withAnimation(.snappy) {
            sortOrderBinding.wrappedValue = sortOrderValue.reversedDirection
        }
    }

    private func collapseAllSections() {
        withAnimation(.snappy) {
            collapsedSectionIDs = currentSectionIDs
        }
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
        searchTextBinding.wrappedValue = ""
        clearAllFilters()
    }

    private func clearAllFilters() {
        filterBinding.wrappedValue = AnimalFilter()
        showRemovedStatusesBinding.wrappedValue = false
        showArchivedRecordsBinding.wrappedValue = false
    }

    private func presentInlineEntryPicker(_ action: () -> Void) {
        inlineEntry.prepareForPickerPresentation()
        action()
    }

    private func requestInlineEntryFocus() {
        inlineEntry.requestFocus()
    }

    private func beginNewInlineEntry() {
        guard !batchMode else { return }

        withAnimation(.snappy) {
            inlineEntry.beginNew()
        }
    }

    private func beginInlineEditing(_ animal: AnimalSummary) {
        guard !batchMode else { return }

        withAnimation(.snappy) {
            inlineEntry.beginEditing(animal, tagColorLibrary: tagColorLibrary)
        }
    }

    private func submitInlineEntry() {
        let trimmedText = inlineEntry.trimmedText
        
        if !trimmedText.isEmpty {
            inlineEntry.ignoresNextFocusLoss = true
        }
        
        commitInlineEntry(startNewEntryAfterCreate: !inlineEntry.isEditing)
    }

    private func commitInlineEntryFromFocusLoss() {
        guard inlineEntry.shouldCommitAfterFocusLoss() else { return }
        commitInlineEntry(startNewEntryAfterCreate: false)
    }

    private func cancelInlineEntry() {
        withAnimation(.snappy) {
            inlineEntry.cancel()
        }
    }

    private func commitInlineEntry(startNewEntryAfterCreate: Bool) {
        do {
            let didCommit = try inlineEntry.commit(
                startNewEntryAfterCreate: startNewEntryAfterCreate,
                colors: tagColorLibrary.colors,
                defaultTagColorID: tagColorLibrary.defaultColorID,
                using: repository
            )

            if didCommit {
                reload()
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func openInlineDetails(_ animalID: UUID) {
        detailAnimalID = animalID
        isShowingInlineDetail = true
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
