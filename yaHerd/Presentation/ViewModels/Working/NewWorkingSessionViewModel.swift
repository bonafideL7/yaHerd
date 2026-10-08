import Foundation

@MainActor
final class NewWorkingSessionViewModel: ObservableObject {
    @Published private(set) var pastures: [PastureOption] = []
    @Published private(set) var templates: [WorkingTreatmentTemplateSummary] = []
    @Published private(set) var animals: [AnimalSummary] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoadingAnimals = false
    @Published private(set) var loadedPastureID: UUID?
    @Published var errorMessage: String?

    private var pastureRepository: any PastureReferenceDataReader
    private var animalReferenceQueryReader: (any AnimalReferenceQueryReading)?
    private var workingRepository: any NewWorkingSessionRepository
    private var requestedPastureID: UUID?

    init(
        pastureRepository: any PastureReferenceDataReader,
        animalReferenceQueryReader: (any AnimalReferenceQueryReading)? = nil,
        workingRepository: any NewWorkingSessionRepository
    ) {
        self.pastureRepository = pastureRepository
        self.animalReferenceQueryReader = animalReferenceQueryReader
        self.workingRepository = workingRepository
    }

    func configure(
        pastureRepository: any PastureReferenceDataReader,
        animalReferenceQueryReader: (any AnimalReferenceQueryReading)?,
        workingRepository: any NewWorkingSessionRepository
    ) {
        self.pastureRepository = pastureRepository
        self.animalReferenceQueryReader = animalReferenceQueryReader
        self.workingRepository = workingRepository
    }

    func load() {
        do {
            pastures = try pastureRepository.fetchPastureOptions()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            templates = try workingRepository.fetchTemplates()
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
        hasLoaded = true
    }

    /// Drop the prior pasture's candidates immediately, before a new asynchronous
    /// page fetch can complete. This also invalidates an older in-flight result.
    func clearCandidates(for pastureID: UUID?) {
        requestedPastureID = pastureID
        loadedPastureID = nil
        animals = []
        isLoadingAnimals = pastureID != nil
    }

    /// Fetch only active, non-archived Animals physically in the selected Pasture.
    /// M9's Core Data reference reader owns filtering, sorting and Herd scoping.
    /// Publish only a complete page sequence; partial pages must not enable Start.
    func loadEligibleAnimals(pastureID: UUID?) async {
        clearCandidates(for: pastureID)
        guard let pastureID else { return }
        guard let animalReferenceQueryReader else {
            isLoadingAnimals = false
            errorMessage = "Working animal reference query is not configured."
            return
        }

        let query = AnimalReferenceQuery(
            pastureScope: .pasture(pastureID),
            location: .pasture,
            sortOrder: .displayTag
        )
        var candidates: [AnimalSummary] = []
        var offset = 0

        do {
            while true {
                try Task.checkCancellation()
                let page = try await animalReferenceQueryReader.fetchAnimalReferencePage(
                    matching: query,
                    page: ReadPageRequest(offset: offset, limit: ReadPageRequest.maximumLimit)
                )
                try Task.checkCancellation()
                guard requestedPastureID == pastureID else { return }

                candidates.append(contentsOf: page.animals)
                if !page.hasMore { break }

                // An inconsistent empty page with hasMore must not spin forever
                // or make a partially loaded working setup usable.
                guard !page.animals.isEmpty else {
                    throw WorkingSessionCandidateLoadingError.emptyIntermediatePage
                }
                offset += page.animals.count
            }

            guard requestedPastureID == pastureID else { return }
            animals = candidates
            loadedPastureID = pastureID
            isLoadingAnimals = false
            errorMessage = nil
        } catch is CancellationError {
            if requestedPastureID == pastureID {
                isLoadingAnimals = false
            }
        } catch {
            guard requestedPastureID == pastureID else { return }
            isLoadingAnimals = false
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func templateDetail(id: UUID) -> WorkingTreatmentTemplateDetailSnapshot? {
        do {
            return try workingRepository.fetchTemplateDetail(id: id)
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return nil
        }
    }

    func eligibleAnimals(pastureID: UUID?) -> [AnimalSummary] {
        guard let pastureID, loadedPastureID == pastureID else { return [] }
        return animals
    }

    @discardableResult
    func startSession(
        date: Date,
        pastureID: UUID,
        treatmentTemplateName: String?,
        plannedTreatments: [WorkingTreatmentPlanItem],
        animalIDs: [UUID]?
    ) async throws -> UUID {
        try await workingRepository.startSession(
            input: WorkingSessionStartInput(
                date: date,
                sourcePastureID: pastureID,
                treatmentTemplateName: treatmentTemplateName,
                plannedTreatments: plannedTreatments,
                animalIDs: animalIDs
            )
        )
    }
}

private enum WorkingSessionCandidateLoadingError: LocalizedError {
    case emptyIntermediatePage

    var errorDescription: String? {
        "Unable to finish loading eligible animals. Reopen Working setup and try again."
    }
}
