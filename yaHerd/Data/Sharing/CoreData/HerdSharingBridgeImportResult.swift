//
//  HerdSharingBridgeImportResult.swift
//  yaHerd
//

import Foundation

struct HerdSharingBridgeImportResult: Equatable {
    let herdName: String
    let insertedPastureGroupCount: Int
    let updatedPastureGroupCount: Int
    let insertedPastureCount: Int
    let updatedPastureCount: Int
    let insertedAnimalCount: Int
    let updatedAnimalCount: Int
    let insertedMovementCount: Int
    let updatedMovementCount: Int
    let insertedStatusRecordCount: Int
    let updatedStatusRecordCount: Int
    let insertedHealthRecordCount: Int
    let updatedHealthRecordCount: Int
    let insertedPregnancyCheckCount: Int
    let updatedPregnancyCheckCount: Int
    let insertedWorkingProtocolTemplateCount: Int
    let updatedWorkingProtocolTemplateCount: Int
    let insertedWorkingSessionCount: Int
    let updatedWorkingSessionCount: Int
    let insertedWorkingQueueItemCount: Int
    let updatedWorkingQueueItemCount: Int
    let insertedWorkingTreatmentRecordCount: Int
    let updatedWorkingTreatmentRecordCount: Int

    var importedPastureGroupCount: Int {
        insertedPastureGroupCount + updatedPastureGroupCount
    }

    var importedPastureCount: Int {
        insertedPastureCount + updatedPastureCount
    }

    var importedAnimalCount: Int {
        insertedAnimalCount + updatedAnimalCount
    }

    var importedMovementCount: Int {
        insertedMovementCount + updatedMovementCount
    }

    var importedStatusRecordCount: Int {
        insertedStatusRecordCount + updatedStatusRecordCount
    }

    var importedHealthRecordCount: Int {
        insertedHealthRecordCount + updatedHealthRecordCount
    }

    var importedPregnancyCheckCount: Int {
        insertedPregnancyCheckCount + updatedPregnancyCheckCount
    }

    var importedWorkingProtocolTemplateCount: Int {
        insertedWorkingProtocolTemplateCount + updatedWorkingProtocolTemplateCount
    }

    var importedWorkingSessionCount: Int {
        insertedWorkingSessionCount + updatedWorkingSessionCount
    }

    var importedWorkingQueueItemCount: Int {
        insertedWorkingQueueItemCount + updatedWorkingQueueItemCount
    }

    var importedWorkingTreatmentRecordCount: Int {
        insertedWorkingTreatmentRecordCount + updatedWorkingTreatmentRecordCount
    }
}
