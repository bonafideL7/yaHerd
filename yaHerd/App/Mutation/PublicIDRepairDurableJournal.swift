#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
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

        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw posixError(operation: "create", path: temporaryURL.path)
        }

        let descriptor = systemOpen(temporaryURL.path, flags: O_WRONLY | O_TRUNC)
        guard descriptor >= 0 else {
            throw posixError(operation: "open", path: temporaryURL.path)
        }

        do {
            try data.withUnsafeBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                var offset = 0
                while offset < bytes.count {
                    let written = systemWrite(
                        descriptor,
                        buffer: baseAddress.advanced(by: offset),
                        count: bytes.count - offset
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
            systemClose(descriptor)
            throw error
        }

        systemClose(descriptor)

        guard systemRename(from: temporaryURL.path, to: fileURL.path) == 0 else {
            throw posixError(operation: "rename", path: fileURL.path)
        }

        let persistedDescriptor = systemOpen(fileURL.path, flags: O_RDONLY)
        guard persistedDescriptor >= 0 else {
            throw posixError(operation: "reopen", path: fileURL.path)
        }
        defer { systemClose(persistedDescriptor) }
        try synchronize(descriptor: persistedDescriptor, path: fileURL.path)
        try synchronizeDirectory(at: directoryURL)
    }

    func remove() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        let result = systemUnlink(fileURL.path)
        if result == 0 {
            try synchronizeDirectory(at: directoryURL)
            return
        }
        if errno == ENOENT { return }
        throw posixError(operation: "remove", path: fileURL.path)
    }

    private func synchronizeDirectory(at directoryURL: URL) throws {
        let descriptor = systemOpen(directoryURL.path, flags: O_RDONLY)
        guard descriptor >= 0 else {
            throw posixError(operation: "open directory", path: directoryURL.path)
        }
        defer { systemClose(descriptor) }
        try synchronize(descriptor: descriptor, path: directoryURL.path)
    }

    private func synchronize(descriptor: Int32, path: String) throws {
        guard systemFsync(descriptor) == 0 else {
            throw posixError(operation: "fsync", path: path)
        }
    }

    private func posixError(operation: String, path: String) -> JournalError {
        JournalError.io(operation: operation, path: path, errorCode: errno)
    }

    private func systemOpen(_ path: String, flags: Int32) -> Int32 {
        path.withCString { pointer in
            #if canImport(Darwin)
            Darwin.open(pointer, flags)
            #else
            Glibc.open(pointer, flags)
            #endif
        }
    }

    private func systemWrite(
        _ descriptor: Int32,
        buffer: UnsafeRawPointer,
        count: Int
    ) -> Int {
        #if canImport(Darwin)
        Darwin.write(descriptor, buffer, count)
        #else
        Glibc.write(descriptor, buffer, count)
        #endif
    }

    private func systemFsync(_ descriptor: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.fsync(descriptor)
        #else
        Glibc.fsync(descriptor)
        #endif
    }

    private func systemClose(_ descriptor: Int32) {
        #if canImport(Darwin)
        _ = Darwin.close(descriptor)
        #else
        _ = Glibc.close(descriptor)
        #endif
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

    private func systemUnlink(_ path: String) -> Int32 {
        path.withCString { pointer in
            #if canImport(Darwin)
            Darwin.unlink(pointer)
            #else
            Glibc.unlink(pointer)
            #endif
        }
    }
}
