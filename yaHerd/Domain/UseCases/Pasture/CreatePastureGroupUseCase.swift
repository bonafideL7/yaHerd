import Foundation

struct CreatePastureGroupUseCase {
    let repository: any PastureGroupCreateRepository

    @discardableResult
    func execute(name: String, grazeDays: Int, restDays: Int) throws -> PastureGroupDetailSnapshot {
        let input = PastureGroupInput(name: name, grazeDays: grazeDays, restDays: restDays)
        let normalized = try PastureGroupInputValidator(repository: repository).validate(input: input)
        return try repository.createGroup(input: normalized)
    }
}
