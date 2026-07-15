//
//  HerdSharingBridgeJournal.swift
//  yaHerd
//

import Foundation

struct HerdSharingBridgeOperationRecord: Codable, Equatable, Identifiable {
  enum State: String, Codable, Equatable {
    case running
    case failed
    case completed
  }

  let id: UUID
  let herdPublicID: UUID
  let direction: HerdSharingBridgeDirection
  let bridgeLocation: String
  let createdAt: Date
  var lastAttemptStartedAt: Date
  var completedAt: Date?
  var attemptCount: Int
  var state: State
  var completedSteps: [HerdSharingBridgeStep]
  var pendingConflictReport: HerdSharingBridgeConflictReport?
  var lastErrorDescription: String?
}

struct HerdSharingBridgeSyncCheckpoint: Codable, Equatable {
  let herdPublicID: UUID
  let direction: HerdSharingBridgeDirection
  let bridgeLocation: String
  let operationID: UUID
  let completedAt: Date
  let recordCounts: [String: Int]
  let reconciliationSummary: String
}

@MainActor
final class HerdSharingBridgeJournal {
  private struct Document: Codable {
    var operations: [HerdSharingBridgeOperationRecord] = []
    var checkpoints: [String: HerdSharingBridgeSyncCheckpoint] = [:]
  }

  private let fileURL: URL
  private let maximumOperationCount: Int
  private var document: Document

  init(fileURL: URL, maximumOperationCount: Int = 100) {
    self.fileURL = fileURL
    self.maximumOperationCount = maximumOperationCount
    document = Self.loadDocument(from: fileURL)
  }

  func begin(
    herdPublicID: UUID,
    direction: HerdSharingBridgeDirection,
    bridgeLocation: String,
    now: Date = .now
  ) throws -> HerdSharingBridgeOperationRecord {
    let operationKey = key(
      herdPublicID: herdPublicID,
      direction: direction,
      bridgeLocation: bridgeLocation
    )
    let existingIndex = document.operations.lastIndex { operation in
      key(
        herdPublicID: operation.herdPublicID,
        direction: operation.direction,
        bridgeLocation: operation.bridgeLocation
      ) == operationKey && operation.state != .completed
    }

    let operation: HerdSharingBridgeOperationRecord
    if let existingIndex {
      document.operations[existingIndex].lastAttemptStartedAt = now
      document.operations[existingIndex].completedAt = nil
      document.operations[existingIndex].attemptCount += 1
      document.operations[existingIndex].state = .running
      document.operations[existingIndex].completedSteps = []
      document.operations[existingIndex].lastErrorDescription = nil
      operation = document.operations[existingIndex]
    } else {
      operation = HerdSharingBridgeOperationRecord(
        id: UUID(),
        herdPublicID: herdPublicID,
        direction: direction,
        bridgeLocation: bridgeLocation,
        createdAt: now,
        lastAttemptStartedAt: now,
        completedAt: nil,
        attemptCount: 1,
        state: .running,
        completedSteps: [],
        pendingConflictReport: nil,
        lastErrorDescription: nil
      )
      document.operations.append(operation)
    }

    trimOperationHistory()
    try persist()
    return operation
  }

  func markCompleted(_ step: HerdSharingBridgeStep, operationID: UUID) throws {
    guard let index = document.operations.firstIndex(where: { $0.id == operationID }) else {
      return
    }
    if !document.operations[index].completedSteps.contains(step) {
      document.operations[index].completedSteps.append(step)
    }
    try persist()
  }

  func recordConflictReport(
    _ report: HerdSharingBridgeConflictReport,
    operationID: UUID
  ) throws {
    guard let index = document.operations.firstIndex(where: { $0.id == operationID }) else {
      return
    }
    document.operations[index].pendingConflictReport = report
    try persist()
  }

  func complete(
    operationID: UUID,
    recordCounts: [String: Int],
    reconciliationSummary: String,
    now: Date = .now
  ) throws {
    guard let index = document.operations.firstIndex(where: { $0.id == operationID }) else {
      return
    }

    document.operations[index].completedAt = now
    document.operations[index].state = .completed
    document.operations[index].lastErrorDescription = nil
    let operation = document.operations[index]
    let checkpoint = HerdSharingBridgeSyncCheckpoint(
      herdPublicID: operation.herdPublicID,
      direction: operation.direction,
      bridgeLocation: operation.bridgeLocation,
      operationID: operation.id,
      completedAt: now,
      recordCounts: recordCounts,
      reconciliationSummary: reconciliationSummary
    )
    document.checkpoints[
      key(
        herdPublicID: operation.herdPublicID,
        direction: operation.direction,
        bridgeLocation: operation.bridgeLocation
      )
    ] = checkpoint
    try persist()
  }

  func fail(operationID: UUID, error: Error) throws {
    guard let index = document.operations.firstIndex(where: { $0.id == operationID }) else {
      return
    }
    document.operations[index].state = .failed
    document.operations[index].lastErrorDescription = String(describing: error)
    try persist()
  }

  func checkpoint(
    herdPublicID: UUID,
    direction: HerdSharingBridgeDirection,
    bridgeLocation: String
  ) -> HerdSharingBridgeSyncCheckpoint? {
    document.checkpoints[
      key(
        herdPublicID: herdPublicID,
        direction: direction,
        bridgeLocation: bridgeLocation
      )
    ]
  }

  func unfinishedOperations() -> [HerdSharingBridgeOperationRecord] {
    document.operations.filter { $0.state != .completed }
  }

  private func key(
    herdPublicID: UUID,
    direction: HerdSharingBridgeDirection,
    bridgeLocation: String
  ) -> String {
    "\(herdPublicID.uuidString)|\(direction.rawValue)|\(bridgeLocation)"
  }

  private func trimOperationHistory() {
    guard document.operations.count > maximumOperationCount else { return }
    document.operations.removeFirst(document.operations.count - maximumOperationCount)
  }

  private func persist() throws {
    let directoryURL = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true,
      attributes: nil
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(document).write(to: fileURL, options: .atomic)
  }

  private static func loadDocument(from fileURL: URL) -> Document {
    guard let data = try? Data(contentsOf: fileURL) else { return Document() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode(Document.self, from: data)) ?? Document()
  }
}
