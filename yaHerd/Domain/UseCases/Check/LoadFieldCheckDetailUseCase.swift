import Foundation

struct LoadFieldCheckDetailUseCase {
    let repository: any FieldCheckRepository

    func execute(id: UUID) throws -> FieldCheckSessionDetailSnapshot? {
        try repository.fetchSessionDetail(id: id)
    }
}
