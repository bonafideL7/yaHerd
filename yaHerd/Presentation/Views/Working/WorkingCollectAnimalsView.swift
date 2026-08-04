//
//  WorkingCollectAnimalsView.swift
//  yaHerd
//

import SwiftUI

struct WorkingCollectAnimalsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    @Environment(AppNavigationState.self) private var navigation
    private var repository: any WorkingCollectAnimalsRepository { workingDependencies.collectAnimalsRepository }
    private var animalSummaryReader: any AnimalSummaryReading { workingDependencies.animalSummaryReader }
    private var pastureReferenceReader: any PastureReferenceDataReader { workingDependencies.pastureReferenceReader }
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    let sessionID: UUID

    @State private var session: WorkingSessionDetailSnapshot?
    @State private var availableAnimals: [AnimalSummary] = []
    @State private var pastureOptions: [PastureOption] = []
    @State private var selectedAnimalIDs: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showingQueryFilters = false

    private var query: AnimalQueryState { navigation.animalQuery }

    private var eligibleAnimals: [AnimalSummary] {
        guard let session else { return [] }
        let existingAnimalIDs = Set(session.queueItems.compactMap(\.animalID))
        let candidates = WorkingCollectAnimalsEligibility.candidates(
            from: availableAnimals,
            sourcePastureID: session.sourcePastureID,
            existingAnimalIDs: existingAnimalIDs
        )

        return AnimalQueryEngine.apply(
            to: candidates,
            query: query.query,
            formatTag: tagColorLibrary.formattedTag(tagNumber:colorID:)
        )
    }

    var body: some View {
        @Bindable var query = query

        NavigationStack {
            List(selection: $selectedAnimalIDs) {
                ForEach(eligibleAnimals) { animal in
                    HStack(spacing: 12) {
                        let def = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)
                        let damDef = tagColorLibrary.resolvedDefinition(tagColorID: animal.damDisplayTagColorID)
                        VStack(alignment: .leading, spacing: 6) {
                            AnimalTagView(
                                tagNumber: animal.displayTagNumber,
                                color: def.color,
                                colorName: def.name,
                                damTagNumber: animal.damDisplayTagNumber,
                                damTagColor: damDef.color,
                                damTagColorName: damDef.name,
                                damTagVisibility: animal.animalType == .calf ? .always : .whenUntagged
                            )
                            Text(animal.sex.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .tag(animal.id)
                }
            }
            .overlay {
                if session == nil {
                    ProgressView()
                } else if eligibleAnimals.isEmpty {
                    ContentUnavailableView(
                        query.hasAnyActiveCriteria ? "No Matching Animals" : "No Animals Available",
                        systemImage: query.hasAnyActiveCriteria ? "magnifyingglass" : "tag",
                        description: Text(
                            query.hasAnyActiveCriteria
                                ? "No eligible animals match the current search and filters."
                                : "No additional animals are eligible for this working session."
                        )
                    )
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Collect")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query.searchText, prompt: "Search tag, color, or name")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                queryControls
                    .background(.bar)
            }
            .task { load() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        collectSelected()
                    }
                    .disabled(selectedAnimalIDs.isEmpty || session == nil)
                    .disabledWhenDataReadOnly()
                }
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                }
            }
            .sheet(isPresented: $showingQueryFilters) {
                AnimalFilterView(
                    filter: $query.filter,
                    showRemovedStatuses: $query.showRemovedStatuses,
                    showArchivedRecords: $query.showArchivedRecords,
                    pastureOptions: pastureOptions
                )
            }
            .alert("Can’t Save", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
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

    private func load() {
        do {
            session = try repository.fetchSessionDetail(id: sessionID)
            availableAnimals = try animalSummaryReader.fetchAnimals()
            pastureOptions = try pastureReferenceReader.fetchPastureOptions()
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }

    private func collectSelected() {
        guard session != nil else { return }
        do {
            try repository.collectAnimals(sessionID: sessionID, animalIDs: Array(selectedAnimalIDs))
            dismiss()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }
}

enum WorkingCollectAnimalsEligibility {
    static func candidates(
        from animals: [AnimalSummary],
        sourcePastureID: UUID?,
        existingAnimalIDs: Set<UUID>
    ) -> [AnimalSummary] {
        guard let sourcePastureID else { return [] }

        return animals.filter { animal in
            animal.status == .active
                && !animal.isArchived
                && animal.pastureID == sourcePastureID
                && animal.location == .pasture
                && !existingAnimalIDs.contains(animal.id)
        }
    }
}
