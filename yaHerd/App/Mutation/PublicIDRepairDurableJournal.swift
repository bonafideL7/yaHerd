import Darwin
import Foundation

/// Disk-backed journal used for the public-ID repair commit boundary.
///
/// Writes are performed to a sibling temporary file, synchronized with `fsync`, atomically
/// renamed into place, and synchronized again after the rename. The containing directory is
/// also synchronized so the renamed directory entry is durable before `persist` returns.
struct PublicIDRepairDurableJournal {
    enum JournalError: LocalizedError, Equatable {
        case io(operation: String, path: String, errorCode: Int32)

        var errorDescription: String? {
            switch self {
            case .io(let operation, let path, let errorCode):
                let message = String(cString: strerror(errorCode))
                return "Public-ID repair journal \(operation) failed for \(path): \(message) (errno \(errorCode))."
            }
        }
    }

    let fileURL: URL

    func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    }

    func persist(_ data: Data) throws {
        let fileManager = FileManager.default
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        var descriptor = Darwin.open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_TRUNC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw posixError(operation: "open", path: temporaryURL.path)
        }

        do {
            try data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                var offset = 0
                while offset < bytes.count {
                    let written = Darwin.write(
                        descriptor,
                        baseAddress.advanced(by: offset),
                        bytes.count - offset
                    )
                    if written < 0 {
                        if errno == EINTR { continue }
                        throw posixError(operation: "write", path: temporaryURL.path)
                    }
                    offset += written
                }
            }
            try synchronize(descriptor: descriptor, path: temporaryURL.path)
        } catch {
            Darwin.close(descriptor)
            descriptor = -1
            throw error
        }

        Darwin.close(descriptor)
        descriptor = -1

        let renameResult = temporaryURL.path.withCString { source in
            fileURL.path.withCString { destination in
                Darwin.rename(source, destination)
            }
        }
        guard renameResult == 0 else {
            throw posixError(operation: "rename", path: fileURL.path)
        }

        let persistedDescriptor = Darwin.open(fileURL.path, O_RDONLY)
        guard persistedDescriptor >= 0 else {
            throw posixError(operation: "reopen", path: fileURL.path)
        }
        defer { Darwin.close(persistedDescriptor) }
        try synchronize(descriptor: persistedDescriptor, path: fileURL.path)
        try synchronizeDirectory(at: directoryURL)
    }

    func remove() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        let result = fileURL.path.withCString { Darwin.unlink($0) }
        if result == 0 {
            try synchronizeDirectory(at: directoryURL)
            return
        }
        if errno == ENOENT { return }
        throw posixError(operation: "remove", path: fileURL.path)
    }

    private func synchronizeDirectory(at directoryURL: URL) throws {
        let descriptor = Darwin.open(directoryURL.path, O_RDONLY)
        guard descriptor >= 0 else {
            throw posixError(operation: "open directory", path: directoryURL.path)
        }
        defer { Darwin.close(descriptor) }
        try synchronize(descriptor: descriptor, path: directoryURL.path)
    }

    private func synchronize(descriptor: Int32, path: String) throws {
        guard Darwin.fsync(descriptor) == 0 else {
            throw posixError(operation: "fsync", path: path)
        }
    }

    private func posixError(operation: String, path: String) -> JournalError {
        JournalError.io(operation: operation, path: path, errorCode: errno)
    }
}
