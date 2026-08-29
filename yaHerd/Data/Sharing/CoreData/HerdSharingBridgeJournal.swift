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

    var isUnfinished: Bool {
      self == .running || self == .failed
    }
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

struct HerdSharingCorruptJournalRecoveryPlan: Equatable, Sendable {
  let herdPublicID: UUID
  let bridgeLocation: String
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
    var document = try loadDocumentIfNeeded()
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
      ) == operationKey && operation.state.isUnfinished
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
    var document = try loadDocumentIfNeeded()
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
    var document = try loadDocumentIfNeeded()
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
    var document = try loadDocumentIfNeeded()
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
    var document = try loadDocumentIfNeeded()
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
    var document = try loadDocumentIfNeeded()
    guard let index = document.operations.firstIndex(where: { $0.id == operationID }) else {
      return
    }
    document.operations[index].state = .failed
    document.operations[index].lastErrorDescription = errorDescription
    try persist(document)
    self.document = document
  }

  /// Supersedes stale bridge work without introducing a new persisted enum value.
  /// Using the existing `completed` state keeps journal files readable by the
  /// previous app build during rollback while ensuring the operation no longer
  /// participates in recovery selection.
  func abandonUnfinishedOperations(
    for herdPublicID: UUID,
    reason: String,
    now: Date = .now
  ) throws {
    var document = try loadDocumentIfNeeded()
    var didChange = false
    for index in document.operations.indices
    where document.operations[index].herdPublicID == herdPublicID
      && document.operations[index].state.isUnfinished
    {
      document.operations[index].state = .completed
      document.operations[index].completedAt = now
      document.operations[index].lastErrorDescription = reason
      didChange = true
    }
    guard didChange else { return }
    try persist(document)
    self.document = document
  }

  /// Supersedes only export recovery work for one concrete bridge relationship.
  /// This is used when an accepted share is still present but has become read-only:
  /// the local SwiftData changes remain intact, while retrying that historical export
  /// is no longer a valid recovery operation. Pending imports are deliberately retained.
  func abandonUnfinishedExports(
    for herdPublicID: UUID,
    bridgeLocation: String,
    reason: String,
    now: Date = .now
  ) throws {
    var document = try loadDocumentIfNeeded()
    var didChange = false
    for index in document.operations.indices
    where document.operations[index].herdPublicID == herdPublicID
      && document.operations[index].direction == .exportToBridge
      && document.operations[index].bridgeLocation == bridgeLocation
      && document.operations[index].state.isUnfinished
    {
      document.operations[index].state = .completed
      document.operations[index].completedAt = now
      document.operations[index].lastErrorDescription = reason
      didChange = true
    }
    guard didChange else { return }
    try persist(document)
    self.document = document
  }

  func checkpoint(
    herdPublicID: UUID,
    direction: HerdSharingBridgeDirection,
    bridgeLocation: String
  ) -> HerdSharingBridgeSyncCheckpoint? {
    guard let document = try? loadDocumentIfNeeded() else { return nil }
    return document.checkpoints[
      key(
        herdPublicID: herdPublicID,
        direction: direction,
        bridgeLocation: bridgeLocation
      )
    ]
  }

  func unfinishedOperations() -> [HerdSharingBridgeOperationRecord] {
    guard let document = try? loadDocumentIfNeeded() else {
      return [corruptJournalSafetyOperation(for: Self.corruptJournalSentinelHerdID)]
    }
    return document.operations.filter { $0.state.isUnfinished }
  }

  func unfinishedOperations(for herdPublicID: UUID) -> [HerdSharingBridgeOperationRecord] {
    guard let document = try? loadDocumentIfNeeded() else {
      return [corruptJournalSafetyOperation(for: herdPublicID)]
    }
    return document.operations.filter {
      $0.herdPublicID == herdPublicID && $0.state.isUnfinished
    }
  }

  /// Preserves the exact unreadable journal bytes before replacing the active document. When a
  /// concrete bridge is available, the replacement atomically includes the failed import-first
  /// recovery operation so no empty-journal window can authorize writes or exports after backup.
  /// If the source cannot be read, the backup cannot be written, or the replacement cannot be
  /// installed, recovery throws and remains fail-closed.
  func backupAndResetCorruptJournal(
    recoveryPlan: HerdSharingCorruptJournalRecoveryPlan? = nil,
    now: Date = .now
  ) throws -> URL {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The persisted sharing recovery journal no longer exists. Refresh sharing state before attempting journal recovery."
      )
    }

    let corruptData: Data
    do {
      corruptData = try Data(contentsOf: fileURL)
    } catch {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The persisted sharing recovery journal could not be read for backup. The journal was not replaced. \(error.localizedDescription)"
      )
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    if (try? decoder.decode(Document.self, from: corruptData)) != nil {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The persisted sharing recovery journal is readable and does not require corrupt-journal recovery."
      )
    }

    let directoryURL = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true,
      attributes: nil
    )
    let backupName = "\(fileURL.deletingPathExtension().lastPathComponent).corrupt-backup-\(Int(now.timeIntervalSince1970))-\(UUID().uuidString.lowercased()).json"
    let backupURL = directoryURL.appendingPathComponent(backupName)

    do {
      try corruptData.write(to: backupURL, options: .atomic)
    } catch {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The corrupt sharing recovery journal could not be backed up. The active journal was not replaced. \(error.localizedDescription)"
      )
    }

    var replacement = Document()
    if let recoveryPlan {
      replacement.operations = [
        HerdSharingBridgeOperationRecord(
          id: UUID(),
          herdPublicID: recoveryPlan.herdPublicID,
          direction: .importFromBridge,
          bridgeLocation: recoveryPlan.bridgeLocation,
          createdAt: now,
          lastAttemptStartedAt: now,
          completedAt: nil,
          attemptCount: 1,
          state: .failed,
          completedSteps: [],
          pendingConflictReport: nil,
          lastErrorDescription: "Scheduled import-first recovery after backing up corrupt journal \(backupURL.lastPathComponent). No local export may resume until this import is reconciled."
        )
      ]
    }

    do {
      try persist(replacement)
      document = replacement
      return backupURL
    } catch {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The corrupt sharing recovery journal was backed up, but a safe replacement journal could not be installed. The original journal remains authoritative and sharing stays blocked. \(error.localizedDescription)"
      )
    }
  }

  nonisolated static func isCorruptJournalSafetyOperation(
    _ operation: HerdSharingBridgeOperationRecord
  ) -> Bool {
    operation.id == corruptJournalSentinelOperationID
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

  private func loadDocumentIfNeeded() throws -> Document {
    if let document { return document }
    let loaded = try Self.loadDocument(from: fileURL)
    document = loaded
    return loaded
  }

  nonisolated private static func loadDocument(from fileURL: URL) throws -> Document {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return Document() }

    let data: Data
    do {
      data = try Data(contentsOf: fileURL)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return Document()
    } catch {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The persisted sharing recovery journal could not be read. Sharing remains blocked so existing recovery evidence is not overwritten. \(error.localizedDescription)"
      )
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      return try decoder.decode(Document.self, from: data)
    } catch {
      throw HerdSharingActionError.bridgeConsistencyFailed(
        "The persisted sharing recovery journal is malformed, truncated, or incompatible. Sharing remains blocked so unfinished recovery evidence is not treated as empty or overwritten."
      )
    }
  }

  private func corruptJournalSafetyOperation(
    for herdPublicID: UUID
  ) -> HerdSharingBridgeOperationRecord {
    HerdSharingBridgeOperationRecord(
      id: Self.corruptJournalSentinelOperationID,
      herdPublicID: herdPublicID,
      direction: .importFromBridge,
      bridgeLocation: "corrupt persisted bridge journal",
      createdAt: Date(timeIntervalSince1970: 0),
      lastAttemptStartedAt: Date(timeIntervalSince1970: 0),
      completedAt: nil,
      attemptCount: 0,
      state: .failed,
      completedSteps: [],
      pendingConflictReport: nil,
      lastErrorDescription:
        "The persisted sharing recovery journal could not be decoded. This synthetic unfinished operation blocks sharing until the journal is repaired or recovered."
    )
  }

  nonisolated private static let corruptJournalSentinelHerdID = UUID(
    uuidString: "00000000-0000-0000-0000-000000000000"
  )!
  nonisolated private static let corruptJournalSentinelOperationID = UUID(
    uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff"
  )!
}
