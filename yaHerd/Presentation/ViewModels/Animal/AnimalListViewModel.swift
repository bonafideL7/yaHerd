import Foundation
import Observation

@MainActor
@Observable
final class AnimalListViewModel {
    private struct DerivationConfiguration {
        let searchText: String
        let sortOrder: AnimalSortOrder
        let filter: AnimalFilter
        let showRemovedStatuses: Bool
        let showArchivedRecords: Bool
        let formatTag: (String, UUID?) -> String
    }

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

    private let derivationActor = AnimalListDerivationActor()
    private var isLoading = false
    private var loadTask: Task<Void, Never>?
    private var derivedStateTask: Task<Void, Never>?
    private var latestDerivationConfiguration: DerivationConfiguration?

    func loadIfNeeded(using readModel: any AnimalListReadModel) async {
        guard !hasLoaded else { return }
        await load(using: readModel)
    }

    func load(using readModel: any AnimalListReadModel) async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            let snapshot = try await readModel.fetchAnimalListSnapshot(pageSize: 250)
            items = snapshot.animals
            pastureOptions = snapshot.pastureOptions
            errorMessage = nil
            hasLoaded = true
            refreshLatestDerivedState()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

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
        if let provider = repository as? any AnimalListReadModelProviding {
            loadTask?.cancel()
            let readModel = provider.animalListReadModel
            loadTask = Task { @MainActor [weak self] in
                await self?.load(using: readModel)
            }
            return
        }

        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
        }

        do {
            items = try repository.fetchAnimals()
            pastureOptions = try pastureRepository.fetchPastureOptions()
            errorMessage = nil
            hasLoaded = true
            refreshLatestDerivedState()
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
        let configuration = DerivationConfiguration(
            searchText: searchText,
            sortOrder: sortOrder,
            filter: filter,
            showRemovedStatuses: showRemovedStatuses,
            showArchivedRecords: showArchivedRecords,
            formatTag: formatTag
        )
        latestDerivationConfiguration = configuration
        scheduleDerivedState(configuration, debounced: debounced)
    }

    func performPrimarySwipeAction(
        animalID: UUID,
        hardDelete: Bool,
        using repository: any AnimalListRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        do {
            if hardDelete {
                try repository.delete(ids: [animalID])
                removeItems(ids: [animalID])
            } else {
                try repository.archive(ids: [animalID])
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
            try repository.restore(ids: [animalID])
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
            try repository.move(ids: ids, toPastureID: pastureID)
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

    private func refreshLatestDerivedState() {
        guard let latestDerivationConfiguration else { return }
        scheduleDerivedState(latestDerivationConfiguration, debounced: false)
    }

    private func scheduleDerivedState(
        _ configuration: DerivationConfiguration,
        debounced: Bool
    ) {
        derivedStateTask?.cancel()

        var formattedTagsByKey: [AnimalListTagKey: String] = [:]
        for animal in items {
            let key = AnimalListTagKey(
                tagNumber: animal.displayTagNumber,
                colorID: animal.displayTagColorID
            )
            formattedTagsByKey[key] = configuration.formatTag(
                animal.displayTagNumber,
                animal.displayTagColorID
            )
        }

        let request = AnimalListDerivationRequest(
            items: items,
            searchText: configuration.searchText,
            sortOrder: configuration.sortOrder,
            filter: configuration.filter,
            showRemovedStatuses: configuration.showRemovedStatuses,
            showArchivedRecords: configuration.showArchivedRecords,
            formattedTagsByKey: formattedTagsByKey
        )
        let derivationActor = self.derivationActor

        derivedStateTask = Task { @MainActor [weak self] in
            if debounced {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            let derivedState = await derivationActor.derive(request)
            guard !Task.isCancelled else { return }
            self?.apply(derivedState)
        }
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

    private func apply(_ state: AnimalListDerivedStateSnapshot) {
        filteredAndSortedAnimals = state.filteredAndSortedAnimals
        groupedAnimals = state.groupedAnimals.map {
            AnimalSection(id: $0.id, title: $0.title, animals: $0.animals)
        }
        shouldUseSections = state.shouldUseSections
        currentSectionIDs = state.currentSectionIDs
        emptyStateConfiguration = AnimalListEmptyStateConfiguration(
            title: state.emptyStateConfiguration.title,
            description: state.emptyStateConfiguration.description,
            systemImage: state.emptyStateConfiguration.systemImage
        )
        hasHiddenOffHerdAnimals = state.hasHiddenOffHerdAnimals
        hasHiddenArchivedRecords = state.hasHiddenArchivedRecords
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
