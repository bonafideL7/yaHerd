//
//  RecoveryModeController.swift
//  yaHerd
//

import Combine
import Foundation
import SwiftData

@MainActor
final class RecoveryModeController: ObservableObject {
  enum RepairResult: Equatable {
    case succeeded(String)
    case failed(String)
  }

  let context: RecoveryModeContext

  @Published var isPresentingCenter = false
  @Published var hasAcknowledgedRepairRisk = false
  @Published private(set) var isPreparingExport = false
  @Published private(set) var isAttemptingRepair = false
  @Published private(set) var exportDocument: RecoveryArchiveDocument?
  @Published private(set) var exportErrorMessage: String?
  @Published private(set) var repairResult: RepairResult?
  @Published private(set) var diagnostics = RecoveryStorageDiagnostics.empty

  private let diagnosticsRepository: (any SyncDiagnosticsRepository)?
  private let fileManager: FileManager

  init(
    context: RecoveryModeContext,
    diagnosticsRepository: (any SyncDiagnosticsRepository)?,
    fileManager: FileManager = .default,
    automaticallyRefreshDiagnostics: Bool = true
  ) {
    self.context = context
    self.diagnosticsRepository = diagnosticsRepository
    self.fileManager = fileManager

    if automaticallyRefreshDiagnostics {
      refreshDiagnostics()
    }
  }

  var exportFilename: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "yaHerd-Recovery-\(formatter.string(from: .now)).tar"
  }

  func prepareExport() {
    guard !isPreparingExport else { return }
    isPreparingExport = true
    exportErrorMessage = nil
    refreshDiagnostics()

    do {
      let entries = try makeRecoveryArchiveEntries()
      let archive = try RecoveryTarArchiveBuilder.makeArchive(entries: entries)
      exportDocument = RecoveryArchiveDocument(data: archive)
    } catch {
      exportDocument = nil
      exportErrorMessage = UserVisibleErrorMessage.make(error)
    }

    isPreparingExport = false
  }

  func clearPreparedExport() {
    exportDocument = nil
  }

  func recordExportFailure(_ error: Error) {
    exportErrorMessage = UserVisibleErrorMessage.make(error)
  }

  func refreshDiagnostics() {
    let counts: SyncDiagnosticsCounts
    let countError: String?

    do {
      counts = try diagnosticsRepository?.fetchCounts() ?? .empty
      countError = nil
    } catch {
      counts = .empty
      countError = UserVisibleErrorMessage.make(error)
    }

    diagnostics = RecoveryStorageDiagnostics(
      generatedAt: .now,
      recoveryStoreCounts: counts,
      recoveryStoreCountError: countError,
      recoverableStoreFiles: recoverableStoreFiles().map { file in
        RecoveryStoreFileDiagnostic(
          archiveName: file.archiveName,
          originalFilename: file.url.lastPathComponent,
          byteCount: file.byteCount,
          modifiedAt: file.modifiedAt
        )
      }
    )
  }

  func attemptPersistentStoreRepair() {
    guard hasAcknowledgedRepairRisk, !isAttemptingRepair else { return }

    isAttemptingRepair = true
    repairResult = nil

    do {
      let container = try ModelContainerFactory.makeContainer(syncMode: .localOnly)
      _ = try container.mainContext.fetchCount(FetchDescriptor<Herd>())
      repairResult = .succeeded(
        "The persistent store opened successfully using the local-only repair probe. Recovery mode remains read-only for this launch. Force quit and reopen yaHerd to return to normal storage."
      )
    } catch {
      repairResult = .failed(
        "The persistent store still could not be opened: \(UserVisibleErrorMessage.make(error))"
      )
    }

    isAttemptingRepair = false
  }

  private func makeRecoveryArchiveEntries() throws -> [RecoveryArchiveEntry] {
    let storeFiles = recoverableStoreFiles()
    let diagnosticsData = try makeDiagnosticsJSON(
      snapshot: diagnostics,
      storeFiles: storeFiles
    )
    let readme = """
      yaHerd recovery export

      This archive was created while yaHerd was running in read-only recovery mode.
      Data changes were disabled and were not written to the in-memory recovery store.

      Contents:
      - RecoveryDiagnostics.json: launch, build, record-count, and file inventory details.
      - Storage/: copies of discoverable yaHerd SwiftData and sharing-bridge store files.

      Keep this archive private. Store files may contain herd and animal records.
      """

    var entries = [
      RecoveryArchiveEntry(
        path: "RecoveryDiagnostics.json",
        data: diagnosticsData,
        modifiedAt: .now
      ),
      RecoveryArchiveEntry(
        path: "README.txt",
        data: Data(readme.utf8),
        modifiedAt: .now
      ),
    ]

    for file in storeFiles {
      guard let data = try? Data(contentsOf: file.url, options: [.mappedIfSafe]) else { continue }
      entries.append(
        RecoveryArchiveEntry(
          path: "Storage/\(file.archiveName)",
          data: data,
          modifiedAt: file.modifiedAt
        )
      )
    }

    return entries
  }

  private func makeDiagnosticsJSON(
    snapshot: RecoveryStorageDiagnostics,
    storeFiles: [RecoverableStoreFile]
  ) throws -> Data {
    let launchSnapshot = AppLaunchDiagnostics.snapshot()
    let payload: [String: Any] = [
      "generatedAt": ISO8601DateFormatter().string(from: snapshot.generatedAt),
      "recoveryEnteredAt": ISO8601DateFormatter().string(from: context.enteredAt),
      "requestedSyncMode": context.requestedSyncMode.rawValue,
      "actualStorageMode": launchSnapshot.actualStorageMode.rawValue,
      "cloudKitOpened": launchSnapshot.cloudKitOpened,
      "startupError": context.startupError,
      "bundleIdentifier": Bundle.main.bundleIdentifier ?? "Unknown",
      "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
      "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
      "recoveryStoreIsInMemory": true,
      "dataMutationsAllowed": false,
      "sharingAndSynchronizationAllowed": false,
      "recoveryStoreCounts": countsDictionary(snapshot.recoveryStoreCounts),
      "recoveryStoreCountError": snapshot.recoveryStoreCountError as Any? ?? NSNull(),
      "recoverableStoreFiles": storeFiles.map { file in
        [
          "archiveName": file.archiveName,
          "originalFilename": file.url.lastPathComponent,
          "byteCount": file.byteCount,
          "modifiedAt": ISO8601DateFormatter().string(from: file.modifiedAt),
        ] as [String: Any]
      },
    ]

    return try JSONSerialization.data(
      withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
  }

  private func countsDictionary(_ counts: SyncDiagnosticsCounts) -> [String: Int] {
    [
      "herds": counts.herds,
      "animals": counts.animals,
      "pastures": counts.pastures,
      "pastureGroups": counts.pastureGroups,
      "healthRecords": counts.healthRecords,
      "pregnancyChecks": counts.pregnancyChecks,
      "movementRecords": counts.movementRecords,
      "statusRecords": counts.statusRecords,
      "workingSessions": counts.workingSessions,
      "workingQueueItems": counts.workingQueueItems,
      "workingTreatmentRecords": counts.workingTreatmentRecords,
      "fieldCheckSessions": counts.fieldCheckSessions,
      "fieldCheckAnimalChecks": counts.fieldCheckAnimalChecks,
      "fieldCheckFindings": counts.fieldCheckFindings,
    ]
  }

  private func recoverableStoreFiles() -> [RecoverableStoreFile] {
    guard
      let applicationSupportURL = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      return []
    }

    let bridgeDirectoryURL = HerdSharingCoreDataStore.defaultStoreDirectoryURL()
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
    guard
      let enumerator = fileManager.enumerator(
        at: applicationSupportURL,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    var results: [RecoverableStoreFile] = []

    for case let url as URL in enumerator {
      guard let values = try? url.resourceValues(forKeys: Set(keys)),
        values.isRegularFile == true,
        shouldIncludeStoreFile(url, bridgeDirectoryURL: bridgeDirectoryURL)
      else {
        continue
      }

      let relativePath = url.path.replacingOccurrences(
        of: applicationSupportURL.path + "/",
        with: ""
      )
      results.append(
        RecoverableStoreFile(
          url: url,
          archiveName: relativePath.replacingOccurrences(of: "/", with: "_"),
          byteCount: values.fileSize ?? 0,
          modifiedAt: values.contentModificationDate ?? .distantPast
        )
      )
    }

    return results.sorted { $0.archiveName < $1.archiveName }
  }

  private func shouldIncludeStoreFile(_ url: URL, bridgeDirectoryURL: URL) -> Bool {
    if url.path.hasPrefix(bridgeDirectoryURL.path + "/") {
      return true
    }

    let name = url.lastPathComponent.lowercased()
    let configuredName = ModelContainerFactory.storeName.lowercased()
    return name.contains(configuredName)
      || name == "default.store"
      || name.hasPrefix("default.store-")
  }
}

private struct RecoverableStoreFile {
  let url: URL
  let archiveName: String
  let byteCount: Int
  let modifiedAt: Date
}
