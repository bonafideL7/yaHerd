import Foundation

@MainActor
struct LoadFieldChecksUseCase {
    let repository: any FieldCheckSessionListReader

    func execute() throws -> [FieldCheckSessionSummary] {
        try repository.fetchSessions()
    }
}
