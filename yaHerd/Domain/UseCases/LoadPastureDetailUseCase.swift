import Foundation

struct LoadPastureDetailUseCase {
    let repository: any PastureRepository

    func execute(id: UUID) throws -> PastureDetailSnapshot {
        guard let detail = try repository.fetchPastureDetail(id: id) else {
            throw PastureValidationError.pastureNotFound
        }
        return detail
    }
}
