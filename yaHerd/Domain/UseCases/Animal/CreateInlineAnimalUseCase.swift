import Foundation

struct CreateInlineAnimalUseCase {
    let repository: any AnimalRepository

    @discardableResult
    func execute(
        name: String,
        tagNumber: String,
        tagColorID: UUID?,
        sex: Sex,
        birthDate: Date,
        pastureID: UUID?
    ) throws -> AnimalDetailSnapshot {
        try CreateAnimalUseCase(repository: repository).execute(
            input: AnimalInput(
                name: name,
                tagNumber: tagNumber,
                tagColorID: tagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : tagColorID,
                sex: sex,
                birthDate: birthDate,
                status: .active,
                pastureID: pastureID,
                sireID: nil,
                damID: nil,
                distinguishingFeatures: [],
                saleDate: nil,
                salePrice: nil,
                reasonSold: nil,
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: nil
            )
        )
    }
}
