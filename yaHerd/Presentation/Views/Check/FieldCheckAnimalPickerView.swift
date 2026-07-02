import SwiftUI

struct FieldCheckLinkedAnimalSelectorRow: View {
    let animals: [FieldCheckAnimalCheckSnapshot]
    @Binding var selectedAnimalID: UUID?

    private var selectedAnimal: FieldCheckAnimalCheckSnapshot? {
        guard let selectedAnimalID else { return nil }
        return animals.first { $0.animalID == selectedAnimalID }
    }

    var body: some View {
        NavigationLink {
            FieldCheckAnimalPickerView(
                animals: animals,
                selectedAnimalID: $selectedAnimalID
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

    let animals: [FieldCheckAnimalCheckSnapshot]
    @Binding var selectedAnimalID: UUID?

    @State private var searchText = ""
    @State private var selectedFilter: FieldCheckLinkedAnimalPickerFilter = .all

    private var animalOptions: [FieldCheckAnimalCheckSnapshot] {
        FieldCheckLinkedAnimalPickerRules.animalOptions(from: animals)
    }

    private var filteredAnimals: [FieldCheckAnimalCheckSnapshot] {
        FieldCheckLinkedAnimalPickerRules.filteredAnimals(
            from: animalOptions,
            searchText: searchText,
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
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty {
            return FieldCheckLinkedAnimalPickerRules.priorityAnimals(
                from: animalOptions,
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

        return "Try a different tag number, name, dam tag, status, or filter."
    }

    var body: some View {
        List {
            noneSection
            selectedAnimalSection
            animalResultsSection
        }
        .navigationTitle("Linked Animal")
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(navigationSubtitle)
        .searchable(
            text: $searchText,
            placement: .automatic,
            prompt: "Search tag, name, dam, status"
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
            Section("Current Selection") {
                animalButton(selectedAnimal)
            } footer: {
                Text("The selected animal does not match the current search or filter, but it remains linked unless you choose another animal or None.")
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
            Text("Search checks tag number, name, dam tag, type, sex, and field-check status. Use filters for missing, flagged, remaining, checked, or added animals.")
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

            if !searchText.isEmpty || selectedFilter != .all {
                Section {
                    Button {
                        searchText = ""
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
                FieldCheckBadge(title: "Checked", tint: .green)
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
    @Environment(\.animalListRepository) private var animalRepository

    @State private var model = FieldCheckTrackedAnimalPickerViewModel()

    let session: FieldCheckSessionDetailSnapshot
    let onSelect: (UUID) -> Bool

    private var existingAnimalIDs: Set<UUID> {
        Set(session.animalChecks.compactMap(\.animalID))
    }

    private var eligibleAnimals: [AnimalSummary] {
        model.eligibleAnimals(
            forPastureID: session.pastureID,
            excluding: existingAnimalIDs
        )
    }

    private var destinationName: String {
        session.pastureName ?? "this pasture"
    }

    var body: some View {
        List {
            Section {
                if eligibleAnimals.isEmpty {
                    ContentUnavailableView(
                        "No Tracked Animals",
                        systemImage: "tag",
                        description: Text("No active tracked herd animals from other pastures match this search.")
                    )
                } else {
                    ForEach(eligibleAnimals) { animal in
                        Button {
                            if onSelect(animal.id) {
                                dismiss()
                            }
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
                Text("Selecting an animal moves it to \(destinationName), records a pasture movement, adds it to this check, and marks it checked. Use Add Offspring from the dam record for new calves.")
            }
        }
        .navigationTitle("Add to Pasture")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.searchText, prompt: "Search animals")
        .task {
            if !model.hasLoaded {
                model.load(using: animalRepository)
            }
        }
        .alert("Can’t Load Animals", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private func moveSummary(for animal: AnimalSummary) -> String {
        let fromName = animal.pastureName ?? "No pasture"
        return "Move from \(fromName) to \(destinationName)"
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
