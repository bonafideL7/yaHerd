import Foundation

struct LoadAnimalEditorOptionsUseCase {
    let animalRepository: any AnimalStatusReferenceReading
    let pastureRepository: any PastureReferenceDataReader

    func execute() throws -> (pastures: [PastureOption], statusReferences: [AnimalStatusReferenceOption]) {
        (
            pastures: try LoadPastureOptionsUseCase(repository: pastureRepository).execute(),
            statusReferences: try animalRepository.fetchStatusReferenceOptions()
        )
    }
}
