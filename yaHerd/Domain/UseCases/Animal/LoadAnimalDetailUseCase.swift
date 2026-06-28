import Foundation

struct LoadAnimalDetailUseCase {
    let repository: any AnimalDetailReading

    func execute(id: UUID) throws -> AnimalDetailSnapshot? {
        try repository.fetchAnimalDetail(id: id)
    }
}
