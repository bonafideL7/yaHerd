import Foundation

@MainActor
final class NewWorkingSessionViewModel: ObservableObject {
    @Published private(set) var pastures: [PastureOption] = []
    @Published private(set) var templates: [WorkingTreatmentTemplateSummary] = []
    @Published private(set) var animals: [AnimalSummary] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var hasLoadedSetupSuccessfully = false
    @Published private(set) var setupLoadErrorMessage: String?
    @Published private(set) var candidateLoadErrorMessage: String?
    @Published private(set) var isLoadingAnimals = false
    @Published private(set) var loadedPastureID: UUID?
    @Published var errorMessage: String?

    private var pastureRepository: any PastureReferenceDataReader
    private var animalReferenceQueryReader: (any AnimalReferenceQueryReading)?
    private var workingRepository: any NewWorkingSessionRepository
    private var requestedPastureID: UUID?
    private var candidateLoadToken = UUID()
    private var loadedCandidateHerdID: UUID?
    private var loadedCandidateSelectionRevision: UInt64?

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
            // Setup is one usable form state: publish neither collection if either
            // source fails, rather than exposing an incomplete template picker.
            let loadedPastures = try pastureRepository.fetchPastureOptions()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let loadedTemplates = try workingRepository.fetchTemplates()

            pastures = loadedPastures
            templates = loadedTemplates
            hasLoadedSetupSuccessfully = true
            if let setupLoadErrorMessage, errorMessage == setupLoadErrorMessage {
                errorMessage = nil
            }
            setupLoadErrorMessage = nil
        } catch {
            pastures = []
            templates = []
            hasLoadedSetupSuccessfully = false
            clearCandidates(for: nil)
            setupLoadErrorMessage = UserVisibleErrorMessage.make(error)
            errorMessage = setupLoadErrorMessage
        }
        hasLoaded = true
    }

    /// A setup belongs to one Herd-selection incarnation. Discard all of its
    /// read models and invalidate any in-flight candidate snapshot.
    func invalidateForHerdChange() {
        clearCandidates(for: nil)
        pastures = []
        templates = []
        hasLoaded = false
        hasLoadedSetupSuccessfully = false
        setupLoadErrorMessage = nil
        errorMessage = nil
    }

    /// Drop the prior pasture's candidates immediately, before a new asynchronous
    /// page fetch can complete. This also invalidates an older in-flight result.
    func clearCandidates(for pastureID: UUID?) {
        // Only dismiss a prior candidate-owned alert. Setup/template/submit
        // errors are independent and must survive candidate changes.
        if let candidateLoadErrorMessage, errorMessage == candidateLoadErrorMessage {
            errorMessage = nil
        }
        candidateLoadErrorMessage = nil
        requestedPastureID = pastureID
        candidateLoadToken = UUID()
        loadedCandidateHerdID = nil
        loadedCandidateSelectionRevision = nil
        loadedPastureID = nil
        animals = []
        isLoadingAnimals = pastureID != nil
    }

    /// Fetch only active, non-archived Animals physically in the selected Pasture.
    /// M9's Core Data reference reader owns filtering, sorting and Herd scoping.
    /// Publish only a complete snapshot; partial results must not enable Start.
    func loadEligibleAnimals(
        pastureID: UUID?,
        currentHerdSelection: any CurrentHerdSelectionReading
    ) async {
        clearCandidates(for: pastureID)
        let loadToken = candidateLoadToken
        guard let pastureID else { return }
        guard let originatingHerdID = currentHerdSelection.currentHerdID else {
            isLoadingAnimals = false
            return
        }
        let originatingSelectionRevision = currentHerdSelection.selectionRevision
        guard let animalReferenceQueryReader else {
            isLoadingAnimals = false
            candidateLoadErrorMessage = "Working animal reference query is not configured."
            if errorMessage == nil {
                errorMessage = candidateLoadErrorMessage
            }
            return
        }

        let query = AnimalReferenceQuery(
            pastureScope: .pasture(pastureID),
            location: .pasture,
            sortOrder: .displayTag
        )
        do {
            // The cohort must come from one pinned Core Data generation. Each
            // independently requested offset page could otherwise skip or
            // duplicate Animals if the Pasture changes during loading.
            let candidates = try await animalReferenceQueryReader.fetchAnimalReferenceSnapshot(
                matching: query
            )
            try Task.checkCancellation()

            guard candidateLoadToken == loadToken,
                  requestedPastureID == pastureID else { return }
            guard currentHerdSelection.currentHerdID == originatingHerdID,
                  currentHerdSelection.selectionRevision == originatingSelectionRevision else {
                isLoadingAnimals = false
                return
            }
            animals = candidates
            loadedCandidateHerdID = originatingHerdID
            loadedCandidateSelectionRevision = originatingSelectionRevision
            loadedPastureID = pastureID
            isLoadingAnimals = false
            // A successful candidate request does not own setup, template,
            // or session errors and must never clear those alerts.
        } catch is CancellationError {
            if candidateLoadToken == loadToken,
               requestedPastureID == pastureID {
                isLoadingAnimals = false
            }
        } catch {
            guard !Task.isCancelled,
                  candidateLoadToken == loadToken,
                  requestedPastureID == pastureID else { return }
            guard currentHerdSelection.currentHerdID == originatingHerdID,
                  currentHerdSelection.selectionRevision == originatingSelectionRevision else {
                isLoadingAnimals = false
                return
            }
            isLoadingAnimals = false
            candidateLoadErrorMessage = UserVisibleErrorMessage.make(error)
            if errorMessage == nil {
                errorMessage = candidateLoadErrorMessage
            }
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

    /// A cached cohort is usable only in the same Herd selection incarnation.
    func hasCurrentCandidates(
        pastureID: UUID?,
        selection: any CurrentHerdSelectionReading
    ) -> Bool {
        guard let pastureID else { return false }
        return loadedPastureID == pastureID
            && loadedCandidateHerdID == selection.currentHerdID
            && loadedCandidateSelectionRevision == selection.selectionRevision
    }

    /// The repository pins the originating Herd when it begins the write.
    /// A finished save must not activate a route in another Herd's navigation.
    @discardableResult
    func startSession(
        date: Date,
        pastureID: UUID,
        treatmentTemplateName: String?,
        plannedTreatments: [WorkingTreatmentPlanItem],
        animalIDs: [UUID]?,
        originatingHerdID: UUID,
        currentHerdSelection: any CurrentHerdSelectionReading,
        selectionIsUnchanged: @escaping @MainActor () -> Bool
    ) async throws -> UUID? {
        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID,
              selectionIsUnchanged() else {
            return nil
        }

        let sessionID = try await workingRepository.startSession(
            input: WorkingSessionStartInput(
                date: date,
                sourcePastureID: pastureID,
                treatmentTemplateName: treatmentTemplateName,
                plannedTreatments: plannedTreatments,
                animalIDs: animalIDs
            )
        )

        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID,
              selectionIsUnchanged() else {
            return nil
        }
        return sessionID
    }
}

