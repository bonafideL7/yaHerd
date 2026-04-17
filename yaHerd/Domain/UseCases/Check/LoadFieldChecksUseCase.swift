import Foundation

struct LoadFieldChecksUseCase {
    let repository: any FieldCheckRepository

    func execute() throws -> [FieldCheckSessionSummary] {
        try repository.fetchSessions()
    }
}
