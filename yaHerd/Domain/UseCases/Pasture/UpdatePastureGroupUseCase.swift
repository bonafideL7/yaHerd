import Foundation

struct UpdatePastureGroupUseCase {
    let repository: any PastureGroupUpdateRepository

    @discardableResult
    func execute(id: UUID, name: String, grazeDays: Int, restDays: Int) throws -> PastureGroupDetailSnapshot {
        let input = PastureGroupInput(name: name, grazeDays: grazeDays, restDays: restDays)
        let normalized = try PastureGroupInputValidator(repository: repository).validate(
            input: input,
            excluding: id
        )
        return try repository.updateGroup(id: id, input: normalized)
    }
}
