//
//  AnimalListView.swift
//

import SwiftUI

#Preview {
    AnimalListView()
        .environment(AppNavigationState())
        .preferredColorScheme(.dark)
}

struct AnimalListView: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(\.animalFeatureDependencies) private var animalDependencies
    private var animalListRepository: any AnimalListRepository { animalDependencies.listRepository }
    private var pastureReferenceDataReader: any PastureReferenceDataReader { animalDependencies.pastureReferenceReader }
    private var sampleDataSeeder: any SampleDataSeeding { animalDependencies.sampleDataSeeder }
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(AppNavigationState.self) private var navigation

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
    private let onOpenAnimal: ((UUID) -> Void)?
    private let onOpenFieldChecks: () -> Void
    private let onOpenWorkSessions: () -> Void
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
        onOpenAnimal: ((UUID) -> Void)? = nil,
        onOpenFieldChecks: @escaping () -> Void = {},
        onOpenWorkSessions: @escaping () -> Void = {},
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
        self.onOpenAnimal = onOpenAnimal
        self.onOpenFieldChecks = onOpenFieldChecks
        self.onOpenWorkSessions = onOpenWorkSessions
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

    private var repository: any AnimalListRepository { animalListRepository }

    private var filteredAndSortedAnimals: [AnimalSummary] {
        viewModel.filteredAndSortedAnimals
    }

    private var groupedAnimals: [AnimalSection] {
        viewModel.groupedAnimals
    }

    private var shouldUseSections: Bool {
        viewModel.shouldUseSections
    }

    private var currentSectionIDs: Set<String> {
        viewModel.currentSectionIDs
    }

    private var canCollapseSections: Bool {
        shouldUseSections && !groupedAnimals.isEmpty
    }

    private var emptyStateConfiguration: AnimalListEmptyStateConfiguration {
        viewModel.emptyStateConfiguration
    }

    private var hasHiddenOffHerdAnimals: Bool {
        viewModel.hasHiddenOffHerdAnimals
    }

    private var hasHiddenArchivedRecords: Bool {
        viewModel.hasHiddenArchivedRecords
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
        .navigationDestination(isPresented: $isShowingInlineDetail) {
            if let detailAnimalID {
                AnimalDetailView(animalID: detailAnimalID)
            }
        }
        .toolbar {
            AnimalListToolbarContent(
                sortOrder: sortOrderValue,
                batchMode: batchMode,
                canCollapseSections: canCollapseSections,
                onReverseSortDirection: reverseSortDirection,
                onCollapseAllSections: collapseAllSections,
                onToggleBatchMode: toggleBatchMode,
                onOpenFieldChecks: onOpenFieldChecks,
                onOpenWorkSessions: onOpenWorkSessions,
                onOpenSettings: onOpenSettings
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomOverlay }
        .overlay(alignment: .bottomTrailing) {
            if dataAccessMode.allowsDataMutations && !batchMode && !inlineEntry.isActive {
                AnimalListFloatingAddButton(
                    bottomPadding: floatingAddButtonBottomPadding,
                    action: presentAddAnimal
                )
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
                moveSelectedAnimals(toPastureID: pasture.id)
            }
        }
        .animalListInlineEntryDialogs(
            sex: $inlineEntry.sex,
            pastureID: $inlineEntry.pastureID,
            birthDate: $inlineEntry.birthDate,
            isShowingSexPicker: $isShowingInlineSexPicker,
            isShowingPasturePicker: $isShowingInlinePasturePicker,
            isShowingBirthDateOptions: $isShowingInlineBirthDateOptions,
            isShowingBirthDatePicker: $isShowingInlineBirthDatePicker,
            pastureOptions: viewModel.pastureOptions,
            onPrepareBirthDatePicker: { inlineEntry.ignoresNextFocusLoss = true },
            onRequestFocus: requestInlineEntryFocus
        )
        .alert("Animal Not Saved", isPresented: errorMessageIsPresented) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            reloadIfNeeded()
        }
        .onChange(of: searchTextValue) { _, _ in
            refreshDerivedState(debounced: true)
        }
        .onChange(of: sortOrderValue) { _, _ in
            refreshDerivedState()
        }
        .onChange(of: filterValue) { _, _ in
            refreshDerivedState()
        }
        .onChange(of: showRemovedStatusesValue) { _, _ in
            refreshDerivedState()
        }
        .onChange(of: showArchivedRecordsValue) { _, _ in
            refreshDerivedState()
        }
        .onChange(of: navigation.presentedSheet) { oldValue, newValue in
            guard oldValue == .addAnimal, newValue == nil else { return }
            reload()
        }
        .onReceive(tagColorLibrary.$colors) { _ in
            refreshDerivedState()
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.snappy, value: batchMode)
        .animation(.snappy, value: selectedAnimalIDs.count)
        .animation(.snappy, value: currentFilterChips.count)
        .profileBodyRecomputation("AnimalListView")
    }

    private var herdList: some View {
        AnimalListContentList(
            groupedAnimals: groupedAnimals,
            shouldUseSections: shouldUseSections,
            batchMode: batchMode,
            selectedAnimalIDs: $selectedAnimalIDs,
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

    private var floatingAddButtonBottomPadding: CGFloat {
        shouldShowFloatingControlBar ? 106 : 24
    }

    private var emptyStateView: some View {
        AnimalListEmptyStateContainer(
            configuration: emptyStateConfiguration,
            hasItems: !viewModel.items.isEmpty,
            filtersAreActive: filtersAreActive,
            hasHiddenOffHerdAnimals: hasHiddenOffHerdAnimals,
            hasHiddenArchivedRecords: hasHiddenArchivedRecords,
            showRemovedStatuses: showRemovedStatusesValue,
            showArchivedRecords: showArchivedRecordsValue,
            colorScheme: colorScheme,
            onStartInlineEntry: beginNewInlineEntry,
            onAddAnimal: presentAddAnimal,
            onAddSampleData: seedSampleData,
            onAddLargeSampleData: seedLargeSampleData,
            onClearFilters: clearAllFilters,
            onShowInactive: { showRemovedStatusesBinding.wrappedValue = true },
            onShowArchivedRecords: { showArchivedRecordsBinding.wrappedValue = true }
        )
    }

    private var bottomOverlay: some View {
        AnimalListBottomOverlay(
            inlineEntryIsActive: inlineEntry.isActive,
            batchMode: batchMode,
            shouldShowFloatingControlBar: shouldShowFloatingControlBar,
            inlineAccessory: { inlineEntryAccessoryBar },
            batchActionBar: { batchActionBar },
            floatingControlBar: { floatingControlBar }
        )
    }

    private var inlineEntryAccessoryBar: some View {
        AnimalListInlineEntryAccessoryBar(
            text: $inlineEntry.text,
            sex: $inlineEntry.sex,
            birthDate: $inlineEntry.birthDate,
            pastureID: $inlineEntry.pastureID,
            pastureOptions: viewModel.pastureOptions,
            isEditing: inlineEntry.isEditing,
            onShowSexPicker: { presentInlineEntryPicker { isShowingInlineSexPicker = true } },
            onShowPasturePicker: { presentInlineEntryPicker { isShowingInlinePasturePicker = true } },
            onShowBirthDateOptions: { presentInlineEntryPicker { isShowingInlineBirthDateOptions = true } },
            onSubmit: submitInlineEntry
        )
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
        AnimalListFilterChipFactory.makeChips(
            filter: filterValue,
            showRemovedStatuses: showRemovedStatusesValue,
            showArchivedRecords: showArchivedRecordsValue,
            pastureName: viewModel.pastureName(for:),
            setFilter: { filterBinding.wrappedValue = $0 },
            setShowRemovedStatuses: { showRemovedStatusesBinding.wrappedValue = $0 },
            setShowArchivedRecords: { showArchivedRecordsBinding.wrappedValue = $0 }
        )
    }

    private var hasAnyActiveCriteria: Bool {
        !searchTextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || filterValue.isActive
        || showRemovedStatusesValue
        || showArchivedRecordsValue
    }

    private func moveSelectedAnimals(toPastureID pastureID: UUID?) {
        viewModel.move(
            ids: Array(selectedAnimalIDs),
            toPastureID: pastureID,
            using: repository,
            pastureRepository: pastureReferenceDataReader
        )
        refreshDerivedState()
        selectedAnimalIDs.removeAll()
        batchMode = false
    }

    private func seedSampleData() {
        sampleDataSeeder.seedSampleDataIfNeeded()
        reload()
    }

    private func seedLargeSampleData() {
        sampleDataSeeder.seedLargeSampleDataIfNeeded()
        reload()
    }

    private func reloadIfNeeded() {
        viewModel.loadIfNeeded(using: repository, pastureRepository: pastureReferenceDataReader)
        refreshDerivedState()
    }

    private func reload() {
        viewModel.load(using: repository, pastureRepository: pastureReferenceDataReader)
        refreshDerivedState()
    }

    private func refreshDerivedState(debounced: Bool = false) {
        viewModel.updateDerivedState(
            searchText: searchTextValue,
            sortOrder: sortOrderValue,
            filter: filterValue,
            showRemovedStatuses: showRemovedStatusesValue,
            showArchivedRecords: showArchivedRecordsValue,
            debounced: debounced
        ) { tagNumber, colorID in
            tagColorLibrary.formattedTag(tagNumber: tagNumber, colorID: colorID)
        }
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
        guard dataAccessMode.allowsDataMutations, !batchMode else { return }

        withAnimation(.snappy) {
            inlineEntry.beginNew()
        }
    }

    private func presentAddAnimal() {
        guard dataAccessMode.allowsDataMutations, !batchMode else { return }
        navigation.present(.addAnimal)
    }

    private func beginInlineEditing(_ animal: AnimalSummary) {
        guard dataAccessMode.allowsDataMutations, !batchMode else {
            openInlineDetails(animal.id)
            return
        }

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
            viewModel.errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    private func openInlineDetails(_ animalID: UUID) {
        if let onOpenAnimal {
            onOpenAnimal(animalID)
        } else {
            detailAnimalID = animalID
            isShowingInlineDetail = true
        }
    }

    private func performPrimarySwipeAction(for animal: AnimalSummary) {
        viewModel.performPrimarySwipeAction(
            animalID: animal.id,
            using: repository,
            pastureRepository: pastureReferenceDataReader
        )
        refreshDerivedState()
    }

    private func restoreArchivedRecord(_ animal: AnimalSummary) {
        viewModel.restore(animalID: animal.id, using: repository, pastureRepository: pastureReferenceDataReader)
        refreshDerivedState()
    }
}
