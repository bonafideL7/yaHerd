//
//  HerdSharingBridgeJournal.swift
//  yaHerd
//

import Foundation

struct HerdSharingBridgeOperationRecord: Codable, Equatable, Identifiable, Sendable {
  enum State: String, Codable, Equatable, Sendable {
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

struct HerdSharingBridgeSyncCheckpoint: Codable, Equatable, Sendable {
  let herdPublicID: UUID
  let direction: HerdSharingBridgeDirection
  let bridgeLocation: String
  let operationID: UUID
  let completedAt: Date
  let recordCounts: [String: Int]
  let reconciliationSummary: String
}

actor HerdSharingBridgeJournal {
  private struct Document: Codable, Sendable {
    var operations: [HerdSharingBridgeOperationRecord] = []
    var checkpoints: [String: HerdSharingBridgeSyncCheckpoint] = [:]
  }

  private let fileURL: URL
  private let maximumOperationCount: Int
  private var document: Document?

  init(fileURL: URL, maximumOperationCount: Int = 100) {
    self.fileURL = fileURL
    self.maximumOperationCount = maximumOperationCount
  }

  func begin(
    herdPublicID: UUID,
    direction: HerdSharingBridgeDirection,
    bridgeLocation: String,
    now: Date = .now
  ) throws -> HerdSharingBridgeOperationRecord {
    var document = loadDocumentIfNeeded()
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

    trimOperationHistory(in: &document)
    try persist(document)
    self.document = document
    return operation
  }

  func markCompleted(_ step: HerdSharingBridgeStep, operationID: UUID) throws {
    var document = loadDocumentIfNeeded()
    guard let index = document.operations.firstIndex(where: { $0.id == operationID }) else {
      return
    }
    if !document.operations[index].completedSteps.contains(step) {
      document.operations[index].completedSteps.append(step)
    }
    try persist(document)
    self.document = document
  }

  func recordConflictReport(
    _ report: HerdSharingBridgeConflictReport,
    operationID: UUID
  ) throws {
    var document = loadDocumentIfNeeded()
    guard let index = document.operations.firstIndex(where: { $0.id == operationID }) else {
      return
    }
    document.operations[index].pendingConflictReport = report
    try persist(document)
    self.document = document
  }

  func recordCommittedImportFailure(
    _ failure: HerdSharingSwiftDataCommittedImportFailure,
    operationID: UUID
  ) throws {
    var document = loadDocumentIfNeeded()
    guard let index = document.operations.firstIndex(where: { $0.id == operationID }) else {
      return
    }

    document.operations[index].pendingConflictReport = failure.conflictReport
    for step in failure.completedSteps
    where !document.operations[index].completedSteps.contains(step) {
      document.operations[index].completedSteps.append(step)
    }
    document.operations[index].state = .failed
    document.operations[index].lastErrorDescription = String(describing: failure.underlyingError)
    try persist(document)
    self.document = document
  }

  func complete(
    operationID: UUID,
    recordCounts: [String: Int],
    reconciliationSummary: String,
    now: Date = .now
  ) throws {
    var document = loadDocumentIfNeeded()
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
    try persist(document)
    self.document = document
  }

  func fail(operationID: UUID, errorDescription: String) throws {
    var document = loadDocumentIfNeeded()
    guard let index = document.operations.firstIndex(where: { $0.id == operationID }) else {
      return
    }
    document.operations[index].state = .failed
    document.operations[index].lastErrorDescription = errorDescription
    try persist(document)
    self.document = document
  }

  func checkpoint(
    herdPublicID: UUID,
    direction: HerdSharingBridgeDirection,
    bridgeLocation: String
  ) -> HerdSharingBridgeSyncCheckpoint? {
    loadDocumentIfNeeded().checkpoints[
      key(
        herdPublicID: herdPublicID,
        direction: direction,
        bridgeLocation: bridgeLocation
      )
    ]
  }

  func unfinishedOperations() -> [HerdSharingBridgeOperationRecord] {
    loadDocumentIfNeeded().operations.filter { $0.state != .completed }
  }

  private func key(
    herdPublicID: UUID,
    direction: HerdSharingBridgeDirection,
    bridgeLocation: String
  ) -> String {
    "\(herdPublicID.uuidString)|\(direction.rawValue)|\(bridgeLocation)"
  }

  private func trimOperationHistory(in document: inout Document) {
    guard document.operations.count > maximumOperationCount else { return }
    document.operations.removeFirst(document.operations.count - maximumOperationCount)
  }

  private func persist(_ document: Document) throws {
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

  private func loadDocumentIfNeeded() -> Document {
    if let document { return document }
    let loaded = Self.loadDocument(from: fileURL)
    document = loaded
    return loaded
  }

  nonisolated private static func loadDocument(from fileURL: URL) -> Document {
    guard let data = try? Data(contentsOf: fileURL) else { return Document() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode(Document.self, from: data)) ?? Document()
  }
}
