import Foundation

struct LoadPastureGroupDetailUseCase {
    let repository: any PastureGroupDetailReader

    func execute(id: UUID) throws -> PastureGroupDetailSnapshot? {
        try repository.fetchPastureGroupDetail(id: id)
    }
}
