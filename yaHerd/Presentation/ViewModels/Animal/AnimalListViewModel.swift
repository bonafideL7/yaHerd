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
        }

        do {
            items = try LoadAnimalsUseCase(repository: repository).execute()
            pastureOptions = try LoadPastureOptionsUseCase(repository: pastureRepository).execute()
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
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
                try await Task.sleep(for: .milliseconds(250))
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
                removeItems(ids: [animalID])
            } else {
                try ArchiveAnimalsUseCase(repository: repository).execute(ids: [animalID])
                updateArchiveState(ids: [animalID], isArchived: true)
            }
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func restore(
        animalID: UUID,
        using repository: any AnimalListRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        do {
            try RestoreAnimalsUseCase(repository: repository).execute(ids: [animalID])
            updateArchiveState(ids: [animalID], isArchived: false)
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
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
            moveItems(ids: ids, toPastureID: pastureID)
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func pastureName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return pastureOptions.first(where: { $0.id == id })?.name
    }

    private func removeItems(ids: [UUID]) {
        let idsToRemove = Set(ids)
        items.removeAll { idsToRemove.contains($0.id) }
    }

    private func updateArchiveState(ids: [UUID], isArchived: Bool) {
        let idsToUpdate = Set(ids)
        items = items.map { animal in
            guard idsToUpdate.contains(animal.id) else { return animal }
            return animal.replacingArchiveState(isArchived)
        }
    }

    private func moveItems(ids: [UUID], toPastureID pastureID: UUID?) {
        let idsToUpdate = Set(ids)
        let destinationName = pastureName(for: pastureID)
        items = items.map { animal in
            guard idsToUpdate.contains(animal.id) else { return animal }
            return animal.replacingPasture(
                pastureID: pastureID,
                pastureName: destinationName
            )
        }
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


private extension AnimalSummary {
    func replacingArchiveState(_ isArchived: Bool) -> AnimalSummary {
        AnimalSummary(
            id: id,
            name: name,
            displayTagNumber: displayTagNumber,
            displayTagColorID: displayTagColorID,
            damDisplayTagNumber: damDisplayTagNumber,
            damDisplayTagColorID: damDisplayTagColorID,
            sex: sex,
            animalType: animalType,
            firstDistinguishingFeature: firstDistinguishingFeature,
            birthDate: birthDate,
            status: status,
            isArchived: isArchived,
            pastureID: pastureID,
            pastureName: pastureName,
            location: location,
            lastPregnancyCheckDate: lastPregnancyCheckDate,
            lastPregnancyStatus: lastPregnancyStatus,
            expectedCalvingDate: expectedCalvingDate,
            lastTreatmentDate: lastTreatmentDate
        )
    }

    func replacingPasture(pastureID: UUID?, pastureName: String?) -> AnimalSummary {
        AnimalSummary(
            id: id,
            name: name,
            displayTagNumber: displayTagNumber,
            displayTagColorID: displayTagColorID,
            damDisplayTagNumber: damDisplayTagNumber,
            damDisplayTagColorID: damDisplayTagColorID,
            sex: sex,
            animalType: animalType,
            firstDistinguishingFeature: firstDistinguishingFeature,
            birthDate: birthDate,
            status: status,
            isArchived: isArchived,
            pastureID: pastureID,
            pastureName: pastureName,
            location: .pasture,
            lastPregnancyCheckDate: lastPregnancyCheckDate,
            lastPregnancyStatus: lastPregnancyStatus,
            expectedCalvingDate: expectedCalvingDate,
            lastTreatmentDate: lastTreatmentDate
        )
    }
}
