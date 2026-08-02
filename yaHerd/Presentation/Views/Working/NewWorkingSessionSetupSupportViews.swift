import SwiftUI

struct WorkingSessionAnimalSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    @Environment(AppNavigationState.self) private var navigation
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    let animals: [AnimalSummary]
    @Binding var selection: Set<UUID>
    @State private var pastureOptions: [PastureOption] = []
    @State private var showingQueryFilters = false

    private var query: AnimalQueryState { navigation.animalQuery }

    private var filteredAnimals: [AnimalSummary] {
        AnimalQueryEngine.apply(
            to: animals,
            query: query.query,
            formatTag: tagColorLibrary.formattedTag(tagNumber:colorID:)
        )
    }

    var body: some View {
        @Bindable var query = query

        NavigationStack {
            List(selection: $selection) {
                ForEach(filteredAnimals) { animal in
                    WorkingSessionAnimalSelectionRow(animal: animal).tag(animal.id)
                }
            }
            .overlay {
                if filteredAnimals.isEmpty {
                    ContentUnavailableView(
                        query.hasAnyActiveCriteria ? "No Matching Animals" : "No Animals Available",
                        systemImage: query.hasAnyActiveCriteria ? "magnifyingglass" : "tag",
                        description: Text(
                            query.hasAnyActiveCriteria
                                ? "No eligible animals match the current search and filters."
                                : "There are no eligible animals to add to this session."
                        )
                    )
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Choose Animals")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query.searchText, prompt: "Search tag, color, or name")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                queryControls
                    .background(.bar)
            }
            .task {
                pastureOptions = (try? workingDependencies.pastureReferenceReader.fetchPastureOptions()) ?? []
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("All") { selection = Set(animals.map(\.id)) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
}

private struct WorkingSessionAnimalSelectionRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    let animal: AnimalSummary

    var body: some View {
        HStack(spacing: 12) {
            let definition = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)
            let damDefinition = tagColorLibrary.resolvedDefinition(tagColorID: animal.damDisplayTagColorID)
            VStack(alignment: .leading, spacing: 6) {
                AnimalTagView(
                    tagNumber: animal.displayTagNumber,
                    color: definition.color,
                    colorName: definition.name,
                    damTagNumber: animal.damDisplayTagNumber,
                    damTagColor: damDefinition.color,
                    damTagColorName: damDefinition.name,
                    damTagVisibility: animal.animalType == .calf ? .always : .whenUntagged
                )
                Text("\(animal.animalType.label) • \(animal.sex.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct WorkingSessionStartBar: View {
    let animalCount: Int
    let isEnabled: Bool
    let statusText: String?
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let statusText {
                Text(statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: onStart) {
                Label(
                    animalCount == 1 ? "Start Session with 1 Animal" : "Start Session with \(animalCount) Animals",
                    systemImage: "wrench.and.screwdriver.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!isEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }
}

struct StartedWorkingSessionSetupRoute: Identifiable, Hashable {
    let id: UUID
}
