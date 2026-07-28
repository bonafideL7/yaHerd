import Foundation

enum WorkingRepositoryError: LocalizedError, Equatable {
    case sessionNotFound
    case sessionStartUnavailable
    case sessionReopenUnavailable
    case sessionAlreadyActive
    case sessionCannotBeReopened
    case queueItemNotFound
    case templateNotFound
    case duplicateTemplateName(String)
    case duplicateTreatmentItemIdentifiers
    case treatmentItemNotInSession
    case invalidTreatmentDose
    case pastureNotFound
    case animalNotFound
    case noEligibleAnimals
    case animalNotEligibleForCollection
    case invalidTagNumber
    case tagReplacementUnavailable
    case duplicateAnimalCollection
    case animalAlreadyInAnotherSession
    case sessionAlreadyFinished
    case duplicateQueueItemAssignments
    case assignmentSetDoesNotMatchSession

    var errorDescription: String? {
        switch self {
        case .sessionNotFound:
            return "Working session not found."
        case .sessionStartUnavailable:
            return "Working sessions are unavailable in the current data mode."
        case .sessionReopenUnavailable:
            return "Reopening working sessions is unavailable in the current data mode."
        case .sessionAlreadyActive:
            return "This working session is already open."
        case .sessionCannotBeReopened:
            return "Only completed working sessions can be reopened."
        case .queueItemNotFound:
            return "Working session animal not found."
        case .templateNotFound:
            return "Treatment template not found."
        case .duplicateTemplateName(let name):
            return "A treatment template named \(name) already exists. Names must be unique."
        case .duplicateTreatmentItemIdentifiers:
            return "Each planned treatment must have a unique identifier."
        case .treatmentItemNotInSession:
            return "A treatment entry does not belong to this working session’s treatment plan."
        case .invalidTreatmentDose:
            return "Treatment dose amounts cannot be negative."
        case .pastureNotFound:
            return "The selected pasture could not be found."
        case .animalNotFound:
            return "One or more selected animals could not be found."
        case .noEligibleAnimals:
            return "Select at least one active animal from the source pasture."
        case .animalNotEligibleForCollection:
            return "One or more selected animals are not active animals in the source pasture."
        case .invalidTagNumber:
            return "Enter a tag number before replacing the tag."
        case .tagReplacementUnavailable:
            return "Tag replacement is unavailable in the current data mode."
        case .duplicateAnimalCollection:
            return "One or more animals are already in this working session."
        case .animalAlreadyInAnotherSession:
            return "One or more animals are already assigned to a different active working session."
        case .sessionAlreadyFinished:
            return "This working session is completed. Reopen it before editing or finishing it again."
        case .duplicateQueueItemAssignments:
            return "A destination was provided more than once for the same animal."
        case .assignmentSetDoesNotMatchSession:
            return "Destination assignments must match every animal in the working session."
        }
    }
}
