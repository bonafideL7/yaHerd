import Foundation

struct LoadAnimalEditorOptionsUseCase {
    let repository: any AnimalRepository

    func execute() throws -> (pastures: [PastureOption], statusReferences: [AnimalStatusReferenceOption]) {
        (
            pastures: try repository.fetchPastureOptions(),
            statusReferences: try repository.fetchStatusReferenceOptions()
        )
    }
}
