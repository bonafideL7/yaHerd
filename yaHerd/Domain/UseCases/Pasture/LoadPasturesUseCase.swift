import Foundation

@MainActor
struct LoadPasturesUseCase {
    let repository: any PastureListReader

    func execute() throws -> [PastureSummary] {
        try repository.fetchPastures()
    }
}
