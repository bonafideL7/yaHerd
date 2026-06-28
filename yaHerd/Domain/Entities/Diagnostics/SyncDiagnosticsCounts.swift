//
//  SyncDiagnosticsCounts.swift
//  yaHerd
//

import Foundation

struct SyncDiagnosticsCounts: Equatable {
    let animals: Int
    let pastures: Int
    let pastureGroups: Int
    let healthRecords: Int
    let pregnancyChecks: Int
    let movementRecords: Int
    let statusRecords: Int
    let workingSessions: Int
    let workingQueueItems: Int
    let workingTreatmentRecords: Int
    let fieldCheckSessions: Int
    let fieldCheckAnimalChecks: Int
    let fieldCheckFindings: Int

    static let empty = SyncDiagnosticsCounts(
        animals: 0,
        pastures: 0,
        pastureGroups: 0,
        healthRecords: 0,
        pregnancyChecks: 0,
        movementRecords: 0,
        statusRecords: 0,
        workingSessions: 0,
        workingQueueItems: 0,
        workingTreatmentRecords: 0,
        fieldCheckSessions: 0,
        fieldCheckAnimalChecks: 0,
        fieldCheckFindings: 0
    )
}
