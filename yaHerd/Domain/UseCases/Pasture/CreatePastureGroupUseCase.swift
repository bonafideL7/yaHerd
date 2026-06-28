import Foundation

struct CreatePastureGroupUseCase {
    let repository: any PastureRepository

    func execute(name: String, grazeDays: Int, restDays: Int) throws {
        let input = PastureGroupInput(name: name, grazeDays: grazeDays, restDays: restDays)
        let normalized = try PastureGroupInputValidator(repository: repository).validate(input: input)
        try repository.createGroup(input: normalized)
    }
}
