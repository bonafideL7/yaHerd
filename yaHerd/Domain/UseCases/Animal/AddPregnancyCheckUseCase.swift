import Foundation

struct AddPregnancyCheckUseCase {
    let repository: any AnimalRepository

    func execute(animalID: UUID, input: PregnancyCheckInput) throws -> AnimalDetailSnapshot {
        try ValidationService.validatePregCheck()
        return try repository.addPregnancyCheck(animalID: animalID, input: input)
    }
}
