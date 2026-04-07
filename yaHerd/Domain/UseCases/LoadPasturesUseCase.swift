import Foundation

struct LoadPasturesUseCase {
    let repository: any PastureRepository

    func execute() throws -> [PastureSummary] {
        try repository.fetchPastures()
    }
}
