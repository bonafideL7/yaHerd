import Foundation

struct LoadAnimalDetailUseCase {
    let repository: any AnimalRepository

    func execute(id: UUID) throws -> AnimalDetailSnapshot? {
        try repository.fetchAnimalDetail(id: id)
    }
}
