//
//  HerdSharingBridgeOperationCoordinator.swift
//  yaHerd
//

import Foundation

@MainActor
final class HerdSharingBridgeOperationCoordinator {
  private let journal: HerdSharingBridgeJournal
  private let failureInjector: HerdSharingBridgeFailureInjector

  init(
    journal: HerdSharingBridgeJournal,
    failureInjector: HerdSharingBridgeFailureInjector = .disabled
  ) {
    self.journal = journal
    self.failureInjector = failureInjector
  }

  func begin(
    herdPublicID: UUID,
    direction: HerdSharingBridgeDirection,
    bridgeLocation: String
  ) throws -> HerdSharingBridgeOperationRecord {
    try journal.begin(
      herdPublicID: herdPublicID,
      direction: direction,
      bridgeLocation: bridgeLocation
    )
  }

  func execute<Value>(
    _ step: HerdSharingBridgeStep,
    operationID: UUID,
    operation: () throws -> Value
  ) throws -> Value {
    let value = try operation()
    try journal.markCompleted(step, operationID: operationID)
    try failureInjector.check(after: step)
    return value
  }

  func execute<Value>(
    _ step: HerdSharingBridgeStep,
    operationID: UUID,
    operation: () async throws -> Value
  ) async throws -> Value {
    let value = try await operation()
    try journal.markCompleted(step, operationID: operationID)
    try failureInjector.check(after: step)
    return value
  }

  func recordConflictReport(
    _ report: HerdSharingBridgeConflictReport,
    operationID: UUID
  ) throws {
    try journal.recordConflictReport(report, operationID: operationID)
  }

  func complete(
    operationID: UUID,
    recordCounts: [String: Int],
    reconciliationSummary: String
  ) throws {
    try journal.complete(
      operationID: operationID,
      recordCounts: recordCounts,
      reconciliationSummary: reconciliationSummary
    )
  }

  func fail(operationID: UUID, error: Error) {
    do {
      try journal.fail(operationID: operationID, error: error)
    } catch {
      ReliabilityLog.syncEvent(
        "HerdSharingBridgeOperationCoordinator.journalFailure",
        detail: String(describing: error)
      )
    }
  }
}
