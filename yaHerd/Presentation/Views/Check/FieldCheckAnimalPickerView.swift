import SwiftUI

struct FieldCheckLinkedAnimalSelectorRow: View {
    let animals: [FieldCheckAnimalCheckSnapshot]
    @Binding var selectedAnimalID: UUID?
    var allowsNone = true

    private var selectedAnimal: FieldCheckAnimalCheckSnapshot? {
        guard let selectedAnimalID else { return nil }
        return animals.first { $0.animalID == selectedAnimalID }
    }

    var body: some View {
        NavigationLink {
            FieldCheckAnimalPickerView(
                animals: animals,
                selectedAnimalID: $selectedAnimalID,
                allowsNone: allowsNone
            )
        } label: {
            LabeledContent("Linked Animal") {
                FieldCheckSelectedAnimalLabel(animal: selectedAnimal)
            }
        }
    }
}

struct FieldCheckAnimalPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigationState.self) private var navigation
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let animals: [FieldCheckAnimalCheckSnapshot]
    @Binding var selectedAnimalID: UUID?
    var allowsNone = true

    @State private var selectedFilter: FieldCheckLinkedAnimalPickerFilter = .all

    private var query: AnimalQueryState { navigation.animalQuery }

    private var animalOptions: [FieldCheckAnimalCheckSnapshot] {
        FieldCheckLinkedAnimalPickerRules.animalOptions(from: animals)
    }

    private var globallyFilteredAnimals: [FieldCheckAnimalCheckSnapshot] {
        FieldCheckAnimalQueryEngine.apply(
            to: animalOptions,
            query: query.query,
            formatTag: tagColorLibrary.formattedTag(tagNumber:colorID:)
        )
    }

    private var filteredAnimals: [FieldCheckAnimalCheckSnapshot] {
        FieldCheckLinkedAnimalPickerRules.filteredAnimals(
            from: globallyFilteredAnimals,
            searchText: "",
            filter: selectedFilter
        )
    }

    private var selectedAnimal: FieldCheckAnimalCheckSnapshot? {
        guard let selectedAnimalID else { return nil }
        return animalOptions.first { $0.animalID == selectedAnimalID }
    }

    private var selectedAnimalIsVisible: Bool {
        guard let selectedAnimalID else { return true }
        return filteredAnimals.contains { $0.animalID == selectedAnimalID }
    }

    private var suggestionAnimals: [FieldCheckAnimalCheckSnapshot] {
        if query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return FieldCheckLinkedAnimalPickerRules.priorityAnimals(
                from: filteredAnimals,
                excluding: selectedAnimalID,
                limit: 6
            )
        }

        return Array(filteredAnimals.prefix(6))
    }

    private var navigationSubtitle: String {
        guard !animalOptions.isEmpty else { return "No roster animals" }
        guard filteredAnimals.count != animalOptions.count else {
            return "\(animalOptions.count) roster animals"
        }
        return "\(filteredAnimals.count) of \(animalOptions.count) roster animals"
    }

    private var emptyStateTitle: String {
        animalOptions.isEmpty ? "No Roster Animals" : "No Matching Animals"
    }

    private var emptyStateDescription: String {
        if animalOptions.isEmpty {
            return "This check does not have any roster animals that can be linked to a finding."
        }

        return "Try a different global animal search or check-specific filter."
    }

    var body: some View {
        @Bindable var query = query

        List {
            if allowsNone {
                noneSection
            }
            selectedAnimalSection
            animalResultsSection
        }
        .navigationTitle("Linked Animal")
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(navigationSubtitle)
        .searchable(
            text: $query.searchText,
            placement: .automatic,
            prompt: "Search tag, name, or dam"
        )
        .searchSuggestions {
            ForEach(suggestionAnimals) { animal in
                Text(suggestionTitle(for: animal))
                    .searchCompletion(FieldCheckLinkedAnimalPickerRules.searchCompletionText(for: animal))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                filterMenu
            }
        }
    }

    private var noneSection: some View {
        Section {
            Button {
                selectedAnimalID = nil
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Text("None")
                        .foregroundStyle(.primary)

                    Spacer(minLength: 12)

                    if selectedAnimalID == nil {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } footer: {
            Text("Leave unlinked for pasture-level findings like water, gate, or fence notes.")
        }
    }

    @ViewBuilder
    private var selectedAnimalSection: some View {
        if let selectedAnimal, !selectedAnimalIsVisible {
            Section {
                animalButton(selectedAnimal)
            } header: {
                Text("Current Selection")
            } footer: {
                Text("The selected animal does not match the current query, but it remains linked unless you choose another animal or None.")
            }
        }
    }

    private var animalResultsSection: some View {
        Section {
            if filteredAnimals.isEmpty {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: "magnifyingglass",
                    description: Text(emptyStateDescription)
                )
            } else {
                ForEach(filteredAnimals) { animal in
                    animalButton(animal)
                }
            }
        } header: {
            HStack {
                Text(selectedFilter.label)
                Spacer()
                Text("\(filteredAnimals.count)")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if allowsNone {
                Text("The global animal query is combined with the check-specific Missing, Flagged, To Check, Seen, and Added filters.")
            } else {
                Text("This finding requires a linked animal. Select the animal that should be marked missing.")
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $selectedFilter) {
                ForEach(FieldCheckLinkedAnimalPickerFilter.allCases) { filter in
                    Label(filter.label, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }

            if query.hasAnyActiveCriteria || selectedFilter != .all {
                Section {
                    Button {
                        query.clearCriteria()
                        selectedFilter = .all
                    } label: {
                        Label("Reset Search and Filter", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        } label: {
            Label(selectedFilter.label, systemImage: selectedFilter.systemImage)
        }
        .accessibilityLabel("Animal filter")
    }

    private func animalButton(_ animal: FieldCheckAnimalCheckSnapshot) -> some View {
        Button {
            selectedAnimalID = animal.animalID
            dismiss()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                FieldCheckAnimalPickerRow(animal: animal)

                if selectedAnimalID == animal.animalID {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .fixedSize()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func suggestionTitle(for animal: FieldCheckAnimalCheckSnapshot) -> String {
        let completionText = FieldCheckLinkedAnimalPickerRules.searchCompletionText(for: animal)
        let status = FieldCheckLinkedAnimalPickerRules.statusSummary(for: animal)
        let trimmedName = animal.animalName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty || trimmedName == completionText {
            return "\(completionText) • \(status)"
        }

        return "\(completionText) • \(trimmedName) • \(status)"
    }
}

private struct FieldCheckSelectedAnimalLabel: View {
    let animal: FieldCheckAnimalCheckSnapshot?

    var body: some View {
        if let animal {
            Text(selectionTitle(for: animal))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("None")
                .foregroundStyle(.secondary)
        }
    }

    private func selectionTitle(for animal: FieldCheckAnimalCheckSnapshot) -> String {
        let trimmedName = animal.animalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedName.isEmpty ? animal.displayTagNumber : "\(animal.displayTagNumber) • \(trimmedName)"
        return "\(base) • \(animal.animalType.label)"
    }
}

private struct FieldCheckAnimalPickerRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let animal: FieldCheckAnimalCheckSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                animalTag
                primaryInfoPill
            }

            VStack(alignment: .trailing, spacing: 8) {
                FieldCheckAnimalPickerStatusPills(animal: animal)
                typeAndSexPill
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var animalTag: some View {
        let definition = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)
        let damDefinition = tagColorLibrary.resolvedDefinition(tagColorID: animal.damDisplayTagColorID)

        return AnimalTagView(
            tagNumber: animal.displayTagNumber,
            color: definition.color,
            colorName: definition.name,
            damTagNumber: animal.damDisplayTagNumber,
            damTagColor: damDefinition.color,
            damTagColorName: damDefinition.name,
            damTagVisibility: animal.animalType == .calf ? .always : .whenUntagged
        )
    }

    private var primaryInfoPill: some View {
        let trimmedName = animal.animalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedName.isEmpty ? animal.animalType.label : trimmedName

        return AnimalListInfoPill(title: title, systemImage: "")
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var typeAndSexPill: some View {
        AnimalListInfoPill(
            title: "\(animal.animalType.label) • \(animal.animalSex.label)",
            systemImage: "tag"
        )
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct FieldCheckAnimalPickerStatusPills: View {
    let animal: FieldCheckAnimalCheckSnapshot

    var body: some View {
        HStack(spacing: 6) {
            if !animal.wasExpectedAtStart {
                FieldCheckBadge(title: "Added", tint: .blue)
            }

            if animal.isMissing {
                FieldCheckBadge(title: "Missing", tint: .orange)
            }

            if animal.wasCounted {
                FieldCheckBadge(title: "Seen", tint: .green)
            }

            if animal.needsAttention {
                FieldCheckBadge(title: "Flagged", tint: .orange)
            }

            if animal.wasExpectedAtStart && !animal.isMissing && !animal.wasCounted && !animal.needsAttention {
                FieldCheckBadge(title: "Expected", tint: .secondary)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct FieldCheckTrackedAnimalPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fieldCheckFeatureDependencies) private var fieldCheckDependencies
    @Environment(AppNavigationState.self) private var navigation
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    private var animalRepository: any AnimalListRepository { fieldCheckDependencies.animalListRepository }

    @State private var model = FieldCheckTrackedAnimalPickerViewModel()
    @State private var pendingAnimal: AnimalSummary?
    @State private var pastureOptions: [PastureOption] = []
    @State private var showingQueryFilters = false

    let session: FieldCheckSessionDetailSnapshot
    let onSelect: (UUID) -> Bool

    private var query: AnimalQueryState { navigation.animalQuery }

    private var existingAnimalIDs: Set<UUID> {
        Set(session.animalChecks.compactMap(\.animalID))
    }

    private var eligibleAnimals: [AnimalSummary] {
        AnimalQueryEngine.apply(
            to: model.animals,
            query: query.query,
            mandatoryConstraint: { animal in
                animal.status == .active
                    && !animal.isArchived
                    && animal.pastureID != session.pastureID
                    && !existingAnimalIDs.contains(animal.id)
            },
            formatTag: tagColorLibrary.formattedTag(tagNumber:colorID:)
        )
    }

    private var destinationName: String {
        session.pastureName ?? "this pasture"
    }

    var body: some View {
        @Bindable var query = query

        List {
            Section {
                if eligibleAnimals.isEmpty {
                    ContentUnavailableView(
                        query.hasAnyActiveCriteria ? "No Matching Animals" : "No Animals Available",
                        systemImage: query.hasAnyActiveCriteria ? "magnifyingglass" : "tag",
                        description: Text(
                            query.hasAnyActiveCriteria
                                ? "No eligible animals match the current global search and filters."
                                : "No active herd animals from other pastures are available."
                        )
                    )
                } else {
                    ForEach(eligibleAnimals) { animal in
                        Button {
                            pendingAnimal = animal
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                AnimalListRowContent(animal: animal)

                                Text(moveSummary(for: animal))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Tracked Herd Animals")
            } footer: {
                Text("Selecting an animal moves it to \(destinationName), records a pasture movement, adds it to this check, and marks it seen. Use Add Offspring from the dam record for new calves.")
            }
        }
        .navigationTitle("Add to Pasture")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query.searchText, prompt: "Search tag, color, or name")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            queryControls
                .background(.bar)
        }
        .task {
            if !model.hasLoaded {
                model.load(using: animalRepository)
            }
            loadPastureOptions()
        }
        .sheet(isPresented: $showingQueryFilters) {
            AnimalFilterView(
                filter: $query.filter,
                showRemovedStatuses: $query.showRemovedStatuses,
                showArchivedRecords: $query.showArchivedRecords,
                pastureOptions: pastureOptions
            )
        }
        .confirmationDialog(
            "Move Animal?",
            isPresented: moveConfirmationBinding,
            titleVisibility: .visible
        ) {
            if let pendingAnimal {
                Button("Move to \(destinationName)") {
                    selectPendingAnimal(pendingAnimal)
                }
            }

            Button("Cancel", role: .cancel) {
                pendingAnimal = nil
            }
        } message: {
            if let pendingAnimal {
                Text("\(pendingAnimal.displayTagNumber) will be moved from \(pendingAnimal.pastureName ?? "No pasture") to \(destinationName), added to this check, and marked seen.")
            }
        }
        .alert("Can’t Load Animals", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private var queryControls: some View {
        @Bindable var query = query

        return AnimalListAdaptiveTabAccessoryControls(
            sortOrder: $query.sortOrder,
            filtersAreActive: query.filtersAreActive,
            activeFilterCount: query.activeFilterCount,
            hasAnyActiveCriteria: query.hasAnyActiveCriteria,
            onShowFilters: { showingQueryFilters = true },
            onClearAllCriteria: { query.clearCriteria() }
        )
    }

    private func loadPastureOptions() {
        do {
            pastureOptions = try fieldCheckDependencies.pastureReferenceReader.fetchPastureOptions()
        } catch {
            model.errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    private func selectPendingAnimal(_ animal: AnimalSummary) {
        if onSelect(animal.id) {
            pendingAnimal = nil
            dismiss()
        }
    }

    private func moveSummary(for animal: AnimalSummary) -> String {
        let fromName = animal.pastureName ?? "No pasture"
        return "Move from \(fromName) to \(destinationName)"
    }

    private var moveConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingAnimal != nil },
            set: { newValue in
                if !newValue {
                    pendingAnimal = nil
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    model.errorMessage = nil
                }
            }
        )
    }
}
