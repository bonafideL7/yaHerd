import Foundation

@MainActor
struct AssignPastureToGroupUseCase {
    let repository: any PastureGroupAssignRepository

    func execute(pastureID: UUID, groupID: UUID?) async throws {
        try repository.validatePastureIDsExist([pastureID])
        if let groupID {
            try repository.validatePastureGroupIDsExist([groupID])
        }
        try await repository.assignPasture(id: pastureID, toGroupID: groupID)
    }
}
