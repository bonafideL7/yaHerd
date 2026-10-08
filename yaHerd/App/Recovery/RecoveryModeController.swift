//
//  RecoveryModeController.swift
//  yaHerd
//

import Combine
@preconcurrency import CoreData
import Foundation

@MainActor
final class RecoveryModeController: ObservableObject {
  enum StoreCheckResult: Equatable {
    case succeeded(String)
    case failed(String)
  }

  let context: RecoveryModeContext

  @Published var isPresentingCenter = false
  @Published private(set) var isPreparingExport = false
  @Published private(set) var isCheckingPersistentStore = false
  @Published private(set) var exportDocument: RecoveryArchiveDocument?
  @Published private(set) var exportErrorMessage: String?
  @Published private(set) var storeCheckResult: StoreCheckResult?
  @Published private(set) var diagnostics = RecoveryStorageDiagnostics.empty
  @Published private(set) var diagnosticsErrorMessage: String?

  private let fileManager: FileManager
  private let applicationSupportURL: URL?

  init(
    context: RecoveryModeContext,
    fileManager: FileManager = .default,
    applicationSupportURL: URL? = nil,
    automaticallyRefreshDiagnostics: Bool = true
  ) {
    self.context = context
    self.fileManager = fileManager
    self.applicationSupportURL = applicationSupportURL

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
      // An incomplete inventory must not be exported as a successful backup.
      if let diagnosticsErrorMessage {
        throw RecoveryStoreInventoryError.unavailable(diagnosticsErrorMessage)
      }
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
    do {
      let files = try recoverableStoreFiles()
      diagnostics = RecoveryStorageDiagnostics(
        generatedAt: .now,
        recoverableStoreFiles: files.map { file in
          RecoveryStoreFileDiagnostic(
            archiveName: file.archiveName,
            originalFilename: file.url.lastPathComponent,
            byteCount: file.byteCount,
            modifiedAt: file.modifiedAt
          )
        }
      )
      diagnosticsErrorMessage = nil
    } catch {
      diagnostics = .empty
      diagnosticsErrorMessage = UserVisibleErrorMessage.make(error)
    }
  }

  /// A non-mutating probe of the existing Core Data store. This never runs a
  /// schema migration, opens a writable store, or changes this recovery session.
  func checkPersistentStoreReadOnly() async {
    guard !isCheckingPersistentStore else { return }
    isCheckingPersistentStore = true
    storeCheckResult = nil
    defer { isCheckingPersistentStore = false }

    do {
      let storeURL = try CoreDataPersistentContainer.defaultStoreURL()
      let assembly = try await CoreDataPersistenceAssembly.load(
        storeURL: storeURL,
        accessMode: .readOnly
      )
      // Reading the current store verifies that this is a usable Core Data
      // graph rather than merely an openable empty SQLite file.
      let context = assembly.contextFactory.makeReadContext()
      let herdCount = try context.performAndWait {
        try context.count(for: NSFetchRequest<CDHerd>(
          entityName: CDHerd.coreDataEntityName
        ))
      }
      guard herdCount == 1 else {
        if herdCount == 0 {
          throw HerdRepositoryError.missingHerd
        }
        throw CoreDataAppHerdBootstrapError.multipleLocalHerds(count: herdCount)
      }
      storeCheckResult = .succeeded(
        "The persistent Core Data store opened read-only. No repair, migration, or write was performed. Recovery mode stays read-only for this launch. Restart yaHerd to retry normal storage."
      )
    } catch {
      storeCheckResult = .failed(
        "The persistent Core Data store still could not be opened read-only: \(UserVisibleErrorMessage.make(error))"
      )
    }
  }

  private func makeRecoveryArchiveEntries() throws -> [RecoveryArchiveEntry] {
    let storeFiles = try recoverableStoreFiles()
    let diagnosticsData = try makeDiagnosticsJSON(
      snapshot: diagnostics,
      storeFiles: storeFiles
    )
    let readme = """
      yaHerd recovery export

      This archive was created while yaHerd was running in read-only recovery mode.
      Data changes were disabled and were not written to the in-memory recovery store.

      Contents:
      - RecoveryDiagnostics.json: launch, build, and local store file inventory details.
      - Storage/: copies of discoverable Core Data SQLite and journal files, plus identified legacy files preserved for backup (without migration).

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
      let data = try Data(contentsOf: file.url, options: [.mappedIfSafe])
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
      "actualStorageMode": launchSnapshot.actualStorageMode.rawValue,
      "startupError": context.startupError,
      "bundleIdentifier": Bundle.main.bundleIdentifier ?? "Unknown",
      "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
      "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
      "recoveryStoreIsInMemory": true,
      "dataMutationsAllowed": false,
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
      withJSONObject: payload,
      options: [.prettyPrinted, .sortedKeys]
    )
  }

  private func recoverableStoreFiles() throws -> [RecoverableStoreFile] {
    guard let appSupportURL = applicationSupportURL ?? fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      throw RecoveryStoreInventoryError.unavailable("Application Support directory is unavailable.")
    }

    // This path mirrors CoreDataPersistentContainer.defaultStoreURL without
    // creating a directory merely to prepare diagnostics.
    let directory = appSupportURL.appendingPathComponent("yaHerd", isDirectory: true)
    let storeName = CoreDataPersistentContainer.storeFileName
    let allowedNames = Set(
      ([""] + CoreDataLegacyStorePreflight.sqliteSidecarSuffixes)
        .map { storeName + $0 }
    )
    let keys: Set<URLResourceKey> = [
      .isRegularFileKey,
      .fileSizeKey,
      .contentModificationDateKey
    ]
    let files: [URL]
    do {
      files = try fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles]
      )
    } catch CocoaError.fileNoSuchFile {
      // No Core Data directory exists on a fresh or preflight-blocked launch.
      files = []
    }

    let coreDataFiles = try files.compactMap { url -> RecoverableStoreFile? in
      guard allowedNames.contains(url.lastPathComponent) else { return nil }
      let values = try url.resourceValues(forKeys: keys)
      guard values.isRegularFile == true else { return nil }
      return RecoverableStoreFile(
        url: url,
        archiveName: url.lastPathComponent,
        byteCount: values.fileSize ?? 0,
        modifiedAt: values.contentModificationDate ?? .distantPast
      )
    }

    // A fresh Core Data launch is blocked when older local store files exist.
    // Make those original files exportable without opening or migrating them.
    let legacyFiles = try CoreDataLegacyStorePreflight.legacyArtifacts(
      in: appSupportURL,
      fileManager: fileManager
    ).map { url -> RecoverableStoreFile in
      let values = try url.resourceValues(forKeys: keys)
      let sourceFolder = url.deletingLastPathComponent().lastPathComponent == "yaHerd"
        ? "LegacyYaHerd"
        : "LegacyAppSupport"
      return RecoverableStoreFile(
        url: url,
        archiveName: "\(sourceFolder)/\(url.lastPathComponent)",
        byteCount: values.fileSize ?? 0,
        modifiedAt: values.contentModificationDate ?? .distantPast
      )
    }

    return (coreDataFiles + legacyFiles)
      .sorted { $0.archiveName < $1.archiveName }
  }
}

private struct RecoverableStoreFile {
  let url: URL
  let archiveName: String
  let byteCount: Int
  let modifiedAt: Date
}

private enum RecoveryStoreInventoryError: LocalizedError {
  case unavailable(String)

  var errorDescription: String? {
    switch self {
    case .unavailable(let message):
      return "Recovery store inventory failed: \(message)"
    }
  }
}
