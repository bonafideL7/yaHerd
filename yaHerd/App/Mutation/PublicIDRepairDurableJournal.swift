#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

/// Disk-backed journal used for the public-ID repair commit boundary.
///
/// The primary journal and a sibling recovery copy are each written through an fsync-backed
/// temporary-file rename. The recovery copy is written first, so it is already a complete durable
/// transaction before the primary write begins. A primary-write failure therefore leaves the
/// recovery copy authoritative rather than turning a safely journaled pre-commit boundary into a
/// rollback. Reads validate the pending-state schema before using either copy to heal the other.
struct PublicIDRepairDurableJournal {
    enum JournalError: LocalizedError, Equatable {
        case io(operation: String, path: String, errorCode: Int32)
        case invalidJSON(path: String)
        case invalidState(path: String)
        case primaryAndRecoveryUnavailable(primary: String, recovery: String)

        var errorDescription: String? {
            switch self {
            case .io(let operation, let path, let errorCode):
                let message = String(cString: strerror(errorCode))
                return "Public-ID repair journal \(operation) failed for \(path): \(message) (errno \(errorCode))."
            case .invalidJSON(let path):
                return "Public-ID repair journal data at \(path) is truncated or malformed."
            case .invalidState(let path):
                return "Public-ID repair journal data at \(path) does not match the pending repair state schema."
            case .primaryAndRecoveryUnavailable(let primary, let recovery):
                return "Neither durable public-ID repair journal copy could be recovered. Primary: \(primary) Recovery: \(recovery)"
            }
        }
    }

    /// Mirrors the durable fields of `PublicIDRepairPendingState` so copy selection can validate
    /// the real journal schema before one durable copy is allowed to overwrite the other.
    private struct PendingStateSchema: Decodable {
        enum Phase: String, Decodable {
            case localCommitPending
            case bridgeConvergenceRequired
        }

        let phase: Phase
        let preparation: PublicIDRepairBridgePreparation
        let report: PublicIDRepairReport
        let resolutions: [PublicIDRepairReferenceResolution]
    }

    let fileURL: URL

    var recoveryFileURL: URL {
        fileURL.appendingPathExtension("recovery")
    }

    func read() throws -> Data? {
        let fileManager = FileManager.default
        let primaryExists = fileManager.fileExists(atPath: fileURL.path)
        let recoveryExists = fileManager.fileExists(atPath: recoveryFileURL.path)
        guard primaryExists || recoveryExists else { return nil }

        let primary = primaryExists ? readResult(at: fileURL) : nil
        let recovery = recoveryExists ? readResult(at: recoveryFileURL) : nil

        switch (primary, recovery) {
        case (.success(let primaryData)?, .success(let recoveryData)?):
            if primaryData == recoveryData {
                return primaryData
            }

            // Persist writes the recovery copy first. When both schema-valid copies differ, the
            // recovery file is the newest complete intended transaction and the primary is stale.
            healRedundantCopy(recoveryData, at: fileURL)
            return recoveryData

        case (.success(let primaryData)?, .failure?):
            // A legacy install may have only the primary copy, or the recovery copy itself may
            // have been damaged. A schema-valid primary can recreate the redundant durable state.
            healRedundantCopy(primaryData, at: recoveryFileURL)
            return primaryData

        case (.success(let primaryData)?, nil):
            healRedundantCopy(primaryData, at: recoveryFileURL)
            return primaryData

        case (.failure, .success(let recoveryData)?),
             (nil, .success(let recoveryData)?):
            healRedundantCopy(recoveryData, at: fileURL)
            return recoveryData

        case (.failure(let primaryError)?, .failure(let recoveryError)?):
            throw JournalError.primaryAndRecoveryUnavailable(
                primary: primaryError.localizedDescription,
                recovery: recoveryError.localizedDescription
            )

        case (.failure(let primaryError)?, nil):
            throw primaryError

        case (nil, .failure(let recoveryError)?):
            throw recoveryError

        case (nil, nil):
            return nil
        }
    }

    func persist(_ data: Data) throws {
        // The recovery copy is the durable commit boundary. Once this succeeds, the caller can
        // safely enter its in-memory pending state even if the redundant primary write fails.
        // A later read will use the schema-valid recovery copy to heal a missing or stale primary.
        try PublicIDRepairDurableFile.persist(data, to: recoveryFileURL)
        do {
            try PublicIDRepairDurableFile.persist(data, to: fileURL)
        } catch {
            // Intentionally keep the durable recovery copy authoritative. Propagating this error
            // would make the caller roll back before assigning its in-memory pending state while
            // leaving a valid recovery journal on disk.
        }
    }

    func remove() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        var retiredURLs: [URL] = []

        // Completion retires each active journal pathname by atomic rename before any best-effort
        // deletion. This is safe for regular files and for an obstructed primary path such as a
        // directory. If retirement of one copy fails, any copy not yet retired remains visible to
        // the next launch, so pending repair state cannot be silently lost. Once both active names
        // are durably absent, stale data at a retired pathname can never resurrect the journal.
        for url in [fileURL, recoveryFileURL] {
            let retiredURL = directoryURL.appendingPathComponent(
                ".\(url.lastPathComponent).\(UUID().uuidString).retired"
            )
            guard systemRename(from: url.path, to: retiredURL.path) == 0 else {
                if errno == ENOENT { continue }
                throw posixError(operation: "retire", path: url.path)
            }
            retiredURLs.append(retiredURL)
            try PublicIDRepairDurableFile.synchronizeDirectory(at: directoryURL)
        }

        // Cleanup no longer participates in correctness after the active pathnames have been
        // retired and fsynced. Leave any artifact quarantined if it cannot be removed safely.
        for retiredURL in retiredURLs {
            try? FileManager.default.removeItem(at: retiredURL)
        }
        if !retiredURLs.isEmpty {
            try? PublicIDRepairDurableFile.synchronizeDirectory(at: directoryURL)
        }
    }

    private func readResult(at url: URL) -> Result<Data, Error> {
        Result { try readValidatedState(at: url) }
    }

    private func readValidatedState(at url: URL) throws -> Data {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw JournalError.invalidJSON(path: url.path)
        }

        do {
            _ = try JSONDecoder().decode(PendingStateSchema.self, from: data)
        } catch {
            throw JournalError.invalidState(path: url.path)
        }
        return data
    }

    private func healRedundantCopy(_ data: Data, at destinationURL: URL) {
        // Once a schema-valid journal copy is available, that state must remain usable even if
        // the sibling path is still unwritable. The pending repair state keeps mutations and sync
        // gated; a later phase transition or relaunch can retry restoring redundancy.
        try? PublicIDRepairDurableFile.persist(data, to: destinationURL)
    }

    private func posixError(operation: String, path: String) -> JournalError {
        JournalError.io(operation: operation, path: path, errorCode: errno)
    }

    private func systemRename(from source: String, to destination: String) -> Int32 {
        source.withCString { sourcePointer in
            destination.withCString { destinationPointer in
                #if canImport(Darwin)
                Darwin.rename(sourcePointer, destinationPointer)
                #else
                Glibc.rename(sourcePointer, destinationPointer)
                #endif
            }
        }
    }
}
