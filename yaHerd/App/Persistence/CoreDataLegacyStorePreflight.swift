import Foundation

/// M10 does not migrate legacy local stores. Do not silently create an empty
/// Core Data Herd over an existing local yaHerd database on first launch.
enum CoreDataLegacyStorePreflight {
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
                for suffix in ["", "-wal", "-shm"] {
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

    var errorDescription: String? {
        switch self {
        case .legacyStoreFound(let files):
            return """
            Existing yaHerd legacy storage was found (\(files.joined(separator: ", "))).
            To protect those records, yaHerd did not create a replacement empty Core Data store.
            Your original files have not been changed. Export them from Recovery Mode.
            Automatic import of legacy stores is not available in this version.
            """
        }
    }
}
