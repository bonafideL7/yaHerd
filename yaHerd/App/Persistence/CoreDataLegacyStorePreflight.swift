import Foundation

/// M10 does not migrate legacy local stores. Do not silently create an empty
/// Core Data Herd over an existing local yaHerd database on first launch.
enum CoreDataLegacyStorePreflight {
    // Both SQLite journal modes must be preserved for first-open safety and backup.
    static let sqliteSidecarSuffixes = ["-wal", "-shm", "-journal"]

    private static let legacyBaseNames = [
        "yaHerdStore.store",
        "yaHerdStore.sqlite",
        "default.store"
    ]

    static func ensureSafeFirstOpen(
        at coreDataStoreURL: URL,
        fileManager: FileManager = .default
    ) throws {
        // Once a Core Data store exists it is authoritative. Retained legacy
        // backups must not block subsequent launches or a future migration.
        guard !fileManager.fileExists(atPath: coreDataStoreURL.path) else { return }

        // A missing main SQLite file does not mean that its journals are safe
        // to discard. Do not create an empty replacement over orphaned sidecars.
        let orphanedCoreDataSidecars = sqliteSidecarSuffixes.compactMap { suffix -> String? in
            let path = coreDataStoreURL.path + suffix
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
                && !isDirectory.boolValue ? coreDataStoreURL.lastPathComponent + suffix : nil
        }
        guard orphanedCoreDataSidecars.isEmpty else {
            throw CoreDataLegacyStorePreflightError.orphanedCoreDataSidecars(
                files: orphanedCoreDataSidecars.sorted()
            )
        }

        let storeDirectory = coreDataStoreURL.deletingLastPathComponent()
        let applicationSupport = storeDirectory.lastPathComponent == "yaHerd"
            ? storeDirectory.deletingLastPathComponent()
            : storeDirectory
        let artifacts = legacyArtifacts(
            in: applicationSupport,
            fileManager: fileManager
        )
        guard artifacts.isEmpty else {
            throw CoreDataLegacyStorePreflightError.legacyStoreFound(
                files: artifacts.map(\.lastPathComponent).sorted()
            )
        }
    }

    /// File inventory only; neither Core Data nor SwiftData opens these files.
    /// Includes SQLite journal sidecars so an interrupted old write is not
    /// mistaken for an empty installation.
    static func legacyArtifacts(
        in applicationSupport: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        let directories = [
            applicationSupport,
            applicationSupport.appendingPathComponent("yaHerd", isDirectory: true)
        ]
        var results: [URL] = []

        for directory in directories {
            for baseName in legacyBaseNames {
                for suffix in [""] + sqliteSidecarSuffixes {
                    let candidate = directory.appendingPathComponent(baseName + suffix)
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                       !isDirectory.boolValue {
                        results.append(candidate)
                    }
                }
            }
        }

        return results.sorted { $0.path < $1.path }
    }
}

enum CoreDataLegacyStorePreflightError: LocalizedError, Equatable {
    case legacyStoreFound(files: [String])
    case orphanedCoreDataSidecars(files: [String])

    var errorDescription: String? {
        switch self {
        case .legacyStoreFound(let files):
            return """
            Existing yaHerd legacy storage was found (\(files.joined(separator: ", "))).
            To protect those records, yaHerd did not create a replacement empty Core Data store.
            Your original files have not been changed. Export them from Recovery Mode.
            Automatic import of legacy stores is not available in this version.
            """
        case .orphanedCoreDataSidecars(let files):
            return """
            Core Data SQLite journal files were found without their main database (\(files.joined(separator: ", "))).
            To protect potentially recoverable records, yaHerd did not create a replacement empty Core Data store.
            These files have not been changed. Export them from Recovery Mode before attempting repair.
            """
        }
    }
}
