//
//  HerdSharingBridgeOperationCoordinator.swift
//  yaHerd
//

import Foundation

@MainActor
final class HerdSharingBridgeOperationCoordinator {
  private let journal: HerdSharingBridgeJournal
  nonisolated private let failureInjector: HerdSharingBridgeFailureInjector

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
  ) async throws -> HerdSharingBridgeOperationRecord {
    try await journal.begin(
      herdPublicID: herdPublicID,
      direction: direction,
      bridgeLocation: bridgeLocation
    )
  }

  func execute<Value>(
    _ step: HerdSharingBridgeStep,
    operationID: UUID,
    operation: () throws -> Value
  ) async throws -> Value {
    let value = try operation()
    try await journal.markCompleted(step, operationID: operationID)
    try failureInjector.check(after: step)
    return value
  }

  func execute<Value>(
    _ step: HerdSharingBridgeStep,
    operationID: UUID,
    operation: () async throws -> Value
  ) async throws -> Value {
    let value = try await operation()
    try await journal.markCompleted(step, operationID: operationID)
    try failureInjector.check(after: step)
    return value
  }

  nonisolated var backgroundFailureInjector: HerdSharingBridgeFailureInjector {
    failureInjector
  }

  func recordCompletedSteps(
    _ steps: [HerdSharingBridgeStep],
    operationID: UUID
  ) async throws {
    for step in steps {
      try await journal.markCompleted(step, operationID: operationID)
    }
  }

  func recordConflictReport(
    _ report: HerdSharingBridgeConflictReport,
    operationID: UUID
  ) async throws {
    try await journal.recordConflictReport(report, operationID: operationID)
  }

  func complete(
    operationID: UUID,
    recordCounts: [String: Int],
    reconciliationSummary: String
  ) async throws {
    try await journal.complete(
      operationID: operationID,
      recordCounts: recordCounts,
      reconciliationSummary: reconciliationSummary
    )
  }

  func fail(operationID: UUID, error: Error) async {
    do {
      try await journal.fail(
        operationID: operationID,
        errorDescription: String(describing: error)
      )
    } catch {
      ReliabilityLog.syncEvent(
        "HerdSharingBridgeOperationCoordinator.journalFailure",
        detail: String(describing: error)
      )
    }
  }
}
