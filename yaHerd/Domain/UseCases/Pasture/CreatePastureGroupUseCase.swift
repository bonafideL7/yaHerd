import Foundation

struct CreatePastureGroupUseCase {
    let repository: any PastureRepository

    func execute(name: String, grazeDays: Int, restDays: Int) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw PastureValidationError.emptyName }
        try repository.createGroup(input: PastureGroupInput(name: trimmedName, grazeDays: grazeDays, restDays: restDays))
    }
}
