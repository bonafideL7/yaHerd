import Foundation

@MainActor
struct LoadAnimalEditorOptionsUseCase {
    let animalRepository: any AnimalStatusReferenceReading
    let pastureRepository: any PastureReferenceDataReader

    func execute() throws -> (pastures: [PastureOption], statusReferences: [AnimalStatusReferenceOption]) {
        (
            pastures: try pastureRepository.fetchPastureOptions(),
            statusReferences: try animalRepository.fetchStatusReferenceOptions()
        )
    }
}
