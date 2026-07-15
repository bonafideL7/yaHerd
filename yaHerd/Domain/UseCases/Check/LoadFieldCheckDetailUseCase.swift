import Foundation

@MainActor
struct LoadFieldCheckDetailUseCase {
    let repository: any FieldCheckSessionDetailReading

    func execute(id: UUID) throws -> FieldCheckSessionDetailSnapshot? {
        try repository.fetchSessionDetail(id: id)
    }
}
