import Foundation

@MainActor
final class NewWorkingSessionViewModel: ObservableObject {
    @Published private(set) var pastures: [PastureOption] = []
    @Published private(set) var templates: [WorkingTreatmentTemplateSummary] = []
    @Published private(set) var animals: [AnimalSummary] = []
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private var pastureRepository: any PastureReferenceDataReader
    private var animalSummaryReader: any AnimalSummaryReading
    private var workingRepository: any NewWorkingSessionRepository

    init(
        pastureRepository: any PastureReferenceDataReader,
        animalSummaryReader: any AnimalSummaryReading,
        workingRepository: any NewWorkingSessionRepository
    ) {
        self.pastureRepository = pastureRepository
        self.animalSummaryReader = animalSummaryReader
        self.workingRepository = workingRepository
    }

    func configure(
        pastureRepository: any PastureReferenceDataReader,
        animalSummaryReader: any AnimalSummaryReading,
        workingRepository: any NewWorkingSessionRepository
    ) {
        self.pastureRepository = pastureRepository
        self.animalSummaryReader = animalSummaryReader
        self.workingRepository = workingRepository
    }

    func load() {
        do {
            pastures = try pastureRepository.fetchPastureOptions()
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            templates = try workingRepository.fetchTemplates()
            animals = try animalSummaryReader.fetchAnimals()
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
        hasLoaded = true
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
        guard let pastureID else { return [] }

        return animals
            .filter { animal in
                animal.status == .active
                    && !animal.isArchived
                    && animal.location == .pasture
                    && animal.pastureID == pastureID
            }
            .sorted {
                $0.displayTagNumber.localizedStandardCompare($1.displayTagNumber) == .orderedAscending
            }
    }

    @discardableResult
    func startSession(
        date: Date,
        pastureID: UUID,
        treatmentTemplateName: String?,
        plannedTreatments: [WorkingTreatmentPlanItem],
        animalIDs: [UUID]?
    ) throws -> UUID {
        try workingRepository.startSession(
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
