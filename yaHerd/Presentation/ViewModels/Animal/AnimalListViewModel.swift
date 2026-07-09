import Foundation
import Observation

@MainActor
@Observable
final class AnimalListViewModel {
    private(set) var items: [AnimalSummary] = []
    private(set) var pastureOptions: [PastureOption] = []
    private(set) var hasLoaded = false
    private(set) var filteredAndSortedAnimals: [AnimalSummary] = []
    private(set) var groupedAnimals: [AnimalSection] = []
    private(set) var shouldUseSections = false
    private(set) var currentSectionIDs: Set<String> = []
    private(set) var emptyStateConfiguration = AnimalListEmptyStateConfiguration(
        title: "No Animals Yet",
        description: "Add your first animal to start building the herd.",
        systemImage: "Cow"
    )
    private(set) var hasHiddenOffHerdAnimals = false
    private(set) var hasHiddenArchivedRecords = false
    var errorMessage: String?

    private var isLoading = false
    private var derivedStateTask: Task<Void, Never>?

    func loadIfNeeded(
        using repository: any AnimalListRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        guard !hasLoaded else { return }
        load(using: repository, pastureRepository: pastureRepository)
    }

    func load(
        using repository: any AnimalListRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            items = try LoadAnimalsUseCase(repository: repository).execute()
            pastureOptions = try LoadPastureOptionsUseCase(repository: pastureRepository).execute()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateDerivedState(
        searchText: String,
        sortOrder: AnimalSortOrder,
        filter: AnimalFilter,
        showRemovedStatuses: Bool,
        showArchivedRecords: Bool,
        debounced: Bool = false,
        formatTag: @escaping (String, UUID?) -> String
    ) {
        derivedStateTask?.cancel()

        guard debounced else {
            applyDerivedState(
                searchText: searchText,
                sortOrder: sortOrder,
                filter: filter,
                showRemovedStatuses: showRemovedStatuses,
                showArchivedRecords: showArchivedRecords,
                formatTag: formatTag
            )
            return
        }

        derivedStateTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            self?.applyDerivedState(
                searchText: searchText,
                sortOrder: sortOrder,
                filter: filter,
                showRemovedStatuses: showRemovedStatuses,
                showArchivedRecords: showArchivedRecords,
                formatTag: formatTag
            )
        }
    }

    func performPrimarySwipeAction(
        animalID: UUID,
        hardDelete: Bool,
        using repository: any AnimalListRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        do {
            if hardDelete {
                try DeleteAnimalsUseCase(repository: repository).execute(ids: [animalID])
            } else {
                try ArchiveAnimalsUseCase(repository: repository).execute(ids: [animalID])
            }
            load(using: repository, pastureRepository: pastureRepository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore(
        animalID: UUID,
        using repository: any AnimalListRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        do {
            try RestoreAnimalsUseCase(repository: repository).execute(ids: [animalID])
            load(using: repository, pastureRepository: pastureRepository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(
        ids: [UUID],
        toPastureID pastureID: UUID?,
        using repository: any AnimalListRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        do {
            try MoveAnimalsUseCase(repository: repository).execute(ids: ids, toPastureID: pastureID)
            load(using: repository, pastureRepository: pastureRepository)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pastureName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return pastureOptions.first(where: { $0.id == id })?.name
    }

    private func applyDerivedState(
        searchText: String,
        sortOrder: AnimalSortOrder,
        filter: AnimalFilter,
        showRemovedStatuses: Bool,
        showArchivedRecords: Bool,
        formatTag: (String, UUID?) -> String
    ) {
        let filtered = AnimalListDerivations.filteredAndSortedAnimals(
            items: items,
            searchText: searchText,
            sortOrder: sortOrder,
            filter: filter,
            showRemovedStatuses: showRemovedStatuses,
            showArchivedRecords: showArchivedRecords,
            formatTag: formatTag
        )
        let sections = AnimalListDerivations.groupedAnimals(filtered, sortOrder: sortOrder)
        let usesSections = AnimalListDerivations.shouldUseSections(for: sortOrder)

        filteredAndSortedAnimals = filtered
        groupedAnimals = sections
        shouldUseSections = usesSections
        currentSectionIDs = usesSections ? Set(sections.map(\.id)) : []
        emptyStateConfiguration = AnimalListDerivations.emptyStateConfiguration(
            items: items,
            searchText: searchText,
            filter: filter,
            showRemovedStatuses: showRemovedStatuses,
            showArchivedRecords: showArchivedRecords
        )
        hasHiddenOffHerdAnimals = AnimalListDerivations.hasHiddenOffHerdAnimals(items: items)
        hasHiddenArchivedRecords = AnimalListDerivations.hasHiddenArchivedRecords(items: items)
    }
}
