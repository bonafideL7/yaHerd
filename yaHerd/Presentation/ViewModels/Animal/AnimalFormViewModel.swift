import Foundation
import Observation

@MainActor
@Observable
final class AnimalFormViewModel {
    var draft: AnimalEditorDraft
    let context: AnimalEditorContext
    private(set) var pastureOptions: [PastureOption] = []
    private(set) var statusReferenceOptions: [AnimalStatusReferenceOption] = []
    var errorMessage: String?

    init(draft: AnimalEditorDraft = AnimalEditorDraft(), context: AnimalEditorContext = .standard) {
        self.draft = draft
        self.context = context
    }

    func loadSupportData(using repository: any AnimalRepository) {
        do {
            let options = try LoadAnimalEditorOptionsUseCase(repository: repository).execute()
            pastureOptions = options.pastures
            statusReferenceOptions = options.statusReferences
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func populate(from detail: AnimalDetailSnapshot) {
        draft = AnimalEditorDraft(detail: detail)
        errorMessage = nil
    }

    func syncPrimaryTag(from detail: AnimalDetailSnapshot) {
        draft.tagNumber = detail.displayTagNumber
        draft.tagColorID = detail.displayTagColorID
    }

    var availableStatusReferences: [AnimalStatusReferenceOption] {
        statusReferenceOptions
            .filter { $0.baseStatus == draft.status }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func makeInput() throws -> AnimalInput {
        try draft.validate()
        let salePrice = try draft.parsedSalePrice()

        return AnimalInput(
            name: draft.normalizedName,
            tagNumber: draft.normalizedTagNumber,
            tagColorID: draft.tagColorID,
            sex: draft.sex,
            birthDate: draft.birthDate,
            status: draft.status,
            pastureID: draft.pastureID,
            sireID: draft.sireID,
            damID: draft.damID,
            distinguishingFeatures: draft.cleanedDistinguishingFeatures,
            saleDate: draft.status == .sold ? draft.saleDate : nil,
            salePrice: draft.status == .sold ? salePrice : nil,
            reasonSold: draft.status == .sold ? draft.normalizedReasonSold : nil,
            deathDate: draft.status == .dead ? draft.deathDate : nil,
            causeOfDeath: draft.status == .dead ? draft.normalizedCauseOfDeath : nil,
            statusReferenceID: draft.statusReferenceID
        )
    }
}
