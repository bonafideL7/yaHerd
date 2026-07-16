import Foundation

enum WorkingRepositoryError: LocalizedError, Equatable {
    case sessionNotFound
    case queueItemNotFound
    case templateNotFound
    case duplicateTemplateName(String)
    case duplicateAnimalCollection
    case animalAlreadyInAnotherSession
    case sessionAlreadyFinished
    case duplicateQueueItemAssignments
    case assignmentSetDoesNotMatchSession

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "Working session not found."
        case .queueItemNotFound:
            return "Working queue item not found."
        case .templateNotFound:
            return "Working protocol template not found."
        case .duplicateTemplateName(let name):
            return "A working protocol template named \(name) already exists. Names must be unique."
        case .duplicateAnimalCollection:
            return "One or more animals are already in this working session."
        case .animalAlreadyInAnotherSession:
            return "One or more animals are already assigned to a different active working session."
        case .sessionAlreadyFinished:
            return "This working session has already been finished."
        case .duplicateQueueItemAssignments:
            return "A destination was provided more than once for the same animal."
        case .assignmentSetDoesNotMatchSession:
            return "Destination assignments must match every animal in the working session."
        }
    }
}
