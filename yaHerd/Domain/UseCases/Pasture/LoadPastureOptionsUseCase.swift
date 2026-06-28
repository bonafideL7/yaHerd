import Foundation

struct LoadPastureOptionsUseCase {
    let repository: any PastureReferenceDataReader

    func execute() throws -> [PastureOption] {
        try repository.fetchPastureOptions()
    }
}
