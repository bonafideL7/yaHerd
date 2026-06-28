import Foundation

struct AssignPastureToGroupUseCase {
    let repository: any PastureGroupAssignRepository

    func execute(pastureID: UUID, groupID: UUID?) throws {
        try repository.validatePastureIDsExist([pastureID])
        if let groupID {
            try repository.validatePastureGroupIDsExist([groupID])
        }
        try repository.assignPasture(id: pastureID, toGroupID: groupID)
    }
}
