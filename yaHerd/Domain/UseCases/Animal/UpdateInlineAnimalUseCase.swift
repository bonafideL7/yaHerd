import Foundation

struct UpdateInlineAnimalUseCase {
    let repository: any AnimalDetailReading & AnimalUpdating

    @discardableResult
    func execute(
        id: UUID,
        name: String?,
        tagNumber: String?,
        tagColorID: UUID?,
        sex: Sex,
        birthDate: Date,
        pastureID: UUID?
    ) throws -> AnimalDetailSnapshot {
        guard let detail = try repository.fetchAnimalDetail(id: id) else {
            throw AnimalValidationError.animalNotFound
        }

        let updatedName = name ?? detail.name
        let updatedTagNumber = tagNumber ?? detail.displayTagNumber
        let updatedTagColorID = tagNumber == nil ? detail.displayTagColorID : tagColorID

        return try UpdateAnimalUseCase(repository: repository).execute(
            id: id,
            input: AnimalInput(
                name: updatedName,
                tagNumber: updatedTagNumber,
                tagColorID: updatedTagColorID,
                sex: sex,
                birthDate: birthDate,
                status: detail.status,
                pastureID: pastureID,
                sireID: detail.sireID,
                damID: detail.damID,
                distinguishingFeatures: detail.distinguishingFeatures,
                saleDate: detail.saleDate,
                salePrice: detail.salePrice,
                reasonSold: detail.reasonSold,
                deathDate: detail.deathDate,
                causeOfDeath: detail.causeOfDeath,
                statusReferenceID: detail.statusReferenceID
            )
        )
    }
}
