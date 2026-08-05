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

    private static let pageSize = ReadPageRequest.defaultLimit

    private var isLoading = false
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var derivedStateTask: Task<Void, Never>?
    private var derivedStateGeneration = 0
    private var lastDerivedStateRequest: DerivedStateRequest?
    private let derivationActor = AnimalListDerivationActor()

    func loadIfNeeded(
        using repository: any AnimalListRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        guard !hasLoaded, !isLoading else { return }
        load(using: repository, pastureRepository: pastureRepository)
    }

    func load(
        using repository: any AnimalListRepository,
        pastureRepository: any PastureReferenceDataReader
    ) {
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        loadTask = nil

        guard let queryReader = repository as? any AnimalListQueryReading else {
            loadSynchronously(
                using: repository,
                pastureRepository: pastureRepository,
                generation: generation
            )
            return
        }

        isLoading = true
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadUsingReadModel(queryReader, generation: generation)
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
        let request = DerivedStateRequest(
            searchText: searchText,
            sortOrder: sortOrder,
            filter: filter,
            showRemovedStatuses: showRemovedStatuses,
            showArchivedRecords: showArchivedRecords,
            formatTag: formatTag
        )
        lastDerivedStateRequest = request
        scheduleDerivedState(request, debounced: debounced)
    }

    func performPrimarySwipeAction(
        animalID: UUID,
        using repository: any AnimalListRepository,
        pastureRepository _: any PastureReferenceDataReader
    ) {
        do {
            try repository.archive(ids: [animalID])
            invalidateCurrentLoad()
            updateArchiveState(ids: [animalID], isArchived: true)
            errorMessage = nil
            hasLoaded = true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func restore(
        animalID: UUID,
        using repository: any AnimalListRepository,
        pastureRepository _: any PastureReferenceDataReader
    ) {
        do {
            try repository.restore(ids: [animalID])
            invalidateCurrentLoad()
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
        pastureRepository _: any PastureReferenceDataReader
    ) {
        do {
            try repository.move(ids: ids, toPastureID: pastureID)
            invalidateCurrentLoad()
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

    private func loadUsingReadModel(
        _ reader: any AnimalListQueryReading,
        generation: Int
    ) async {
        defer {
            if generation == loadGeneration {
                isLoading = false
                loadTask = nil
            }
        }

        do {
            let loaded = try await PerformanceLog.measureAsync("AnimalList.load") {
                async let pastureOptions = reader.fetchAnimalPastureOptions(limit: 500)
                let animals = try await fetchAllAnimalPages(using: reader)
                return (animals, try await pastureOptions)
            }

            guard !Task.isCancelled, generation == loadGeneration else { return }
            items = loaded.0
            pastureOptions = loaded.1
            errorMessage = nil
            hasLoaded = true
            refreshLastDerivedState()
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    private func loadSynchronously(
        using repository: any AnimalListRepository,
        pastureRepository: any PastureReferenceDataReader,
        generation: Int
    ) {
        isLoading = true
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        do {
            let loadedItems = try repository.fetchAnimals()
            let loadedPastures = try pastureRepository.fetchPastureOptions()
            guard generation == loadGeneration else { return }
            items = loadedItems
            pastureOptions = loadedPastures
            errorMessage = nil
            hasLoaded = true
            refreshLastDerivedState()
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    private func fetchAllAnimalPages(
        using reader: any AnimalListQueryReading
    ) async throws -> [AnimalSummary] {
        var offset = 0
        var animals: [AnimalSummary] = []

        while true {
            try Task.checkCancellation()
            let page = try await reader.fetchAnimalSummaryPage(
                ReadPageRequest(offset: offset, limit: Self.pageSize)
            )
            animals.append(contentsOf: page.animals)

            guard page.hasMore else { return animals }
            guard !page.animals.isEmpty else { return animals }
            offset += page.animals.count
        }
    }

    private func invalidateCurrentLoad() {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    private func refreshLastDerivedState() {
        guard let lastDerivedStateRequest else { return }
        scheduleDerivedState(lastDerivedStateRequest, debounced: false)
    }

    private func scheduleDerivedState(
        _ request: DerivedStateRequest,
        debounced: Bool
    ) {
        derivedStateTask?.cancel()
        derivedStateGeneration += 1
        let generation = derivedStateGeneration
        let itemsSnapshot = items
        var formattedTags: [AnimalFormattedTagKey: String] = [:]
        formattedTags.reserveCapacity(itemsSnapshot.count)
        for animal in itemsSnapshot {
            let key = AnimalFormattedTagKey(
                number: animal.displayTagNumber,
                colorID: animal.displayTagColorID
            )
            formattedTags[key] = request.formatTag(key.number, key.colorID)
        }
        let derivationActor = derivationActor

        derivedStateTask = Task { @MainActor [weak self] in
            if debounced {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            let snapshot = await derivationActor.makeSnapshot(
                items: itemsSnapshot,
                searchText: request.searchText,
                sortOrder: request.sortOrder,
                filter: request.filter,
                showRemovedStatuses: request.showRemovedStatuses,
                showArchivedRecords: request.showArchivedRecords,
                formattedTags: formattedTags
            )
            guard !Task.isCancelled else { return }
            guard let self, generation == self.derivedStateGeneration else { return }
            self.applyDerivedState(snapshot)
        }
    }

    private func applyDerivedState(_ snapshot: AnimalListDerivedStateSnapshot) {
        filteredAndSortedAnimals = snapshot.filteredAndSortedAnimals
        groupedAnimals = snapshot.groupedAnimals
        shouldUseSections = snapshot.shouldUseSections
        currentSectionIDs = snapshot.currentSectionIDs
        emptyStateConfiguration = snapshot.emptyStateConfiguration
        hasHiddenOffHerdAnimals = snapshot.hasHiddenOffHerdAnimals
        hasHiddenArchivedRecords = snapshot.hasHiddenArchivedRecords
    }

    private func updateArchiveState(ids: [UUID], isArchived: Bool) {
        let idsToUpdate = Set(ids)
        items = items.map { animal in
            guard idsToUpdate.contains(animal.id) else { return animal }
            return animal.replacingArchiveState(isArchived)
        }
        refreshLastDerivedState()
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
        refreshLastDerivedState()
    }
}

private struct DerivedStateRequest {
    let searchText: String
    let sortOrder: AnimalSortOrder
    let filter: AnimalFilter
    let showRemovedStatuses: Bool
    let showArchivedRecords: Bool
    let formatTag: (String, UUID?) -> String
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
