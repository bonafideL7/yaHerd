import Foundation

struct AddHealthRecordUseCase {
    let repository: any AnimalRepository

    func execute(animalID: UUID, date: Date, treatment: String, notes: String?) throws -> AnimalDetailSnapshot {
        try ValidationService.validateHealthRecord(treatment: treatment)
        return try repository.addHealthRecord(animalID: animalID, input: HealthRecordInput(date: date, treatment: treatment, notes: notes))
    }
}
