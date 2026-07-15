//
//  HerdSharingBridgeExportResult.swift
//  yaHerd
//

struct HerdSharingBridgeExportResult: Equatable {
  let herdName: String
  let writeTargetDescription: String
  let didUpdateExistingCloudKitShare: Bool
  let exportedTagColorDefinitionCount: Int
  let exportedStatusReferenceCount: Int
  let exportedAnimalTagCount: Int
  let exportedPastureGroupCount: Int
  let exportedPastureCount: Int
  let exportedAnimalCount: Int
  let exportedMovementCount: Int
  let exportedStatusRecordCount: Int
  let exportedHealthRecordCount: Int
  let exportedPregnancyCheckCount: Int
  let exportedWorkingProtocolTemplateCount: Int
  let exportedWorkingSessionCount: Int
  let exportedWorkingQueueItemCount: Int
  let exportedWorkingTreatmentRecordCount: Int
  let exportedFieldCheckSessionCount: Int
  let exportedFieldCheckAnimalCheckCount: Int
  let exportedFieldCheckFindingCount: Int
  let exportedDeletedRecordCount: Int
  let reconciliationReport: HerdSharingBridgeReconciliationReport

  var reconciliationSummary: String {
    reconciliationReport.summary
  }

  var exportedRecordCount: Int {
    1
      + exportedTagColorDefinitionCount
      + exportedStatusReferenceCount
      + exportedAnimalTagCount
      + exportedPastureGroupCount
      + exportedPastureCount
      + exportedAnimalCount
      + exportedMovementCount
      + exportedStatusRecordCount
      + exportedHealthRecordCount
      + exportedPregnancyCheckCount
      + exportedWorkingProtocolTemplateCount
      + exportedWorkingSessionCount
      + exportedWorkingQueueItemCount
      + exportedWorkingTreatmentRecordCount
      + exportedFieldCheckSessionCount
      + exportedFieldCheckAnimalCheckCount
      + exportedFieldCheckFindingCount
      + exportedDeletedRecordCount
  }
}
