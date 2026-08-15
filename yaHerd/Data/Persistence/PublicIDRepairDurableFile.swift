#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

/// Persists repair-owned files through the same durable temporary-file boundary used by the
/// public-ID repair journal. A successful return means both the final file and its directory entry
/// have been synchronized before any caller may journal a reference to that file.
enum PublicIDRepairDurableFile {
    enum PersistenceError: LocalizedError, Equatable {
        case io(operation: String, path: String, errorCode: Int32)

        var errorDescription: String? {
            switch self {
            case .io(let operation, let path, let errorCode):
                let message = String(cString: strerror(errorCode))
                return "Public-ID repair durable file \(operation) failed for \(path): \(message) (errno \(errorCode))."
            }
        }
    }

    static func persist(_ data: Data, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let directoryURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp"
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
                    guard written > 0 else {
                        throw PersistenceError.io(
                            operation: "write",
                            path: temporaryURL.path,
                            errorCode: EIO
                        )
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

        guard systemRename(from: temporaryURL.path, to: destinationURL.path) == 0 else {
            throw posixError(operation: "rename", path: destinationURL.path)
        }

        let persistedDescriptor = systemOpen(destinationURL.path, flags: O_RDONLY)
        guard persistedDescriptor >= 0 else {
            throw posixError(operation: "reopen", path: destinationURL.path)
        }
        defer { systemClose(persistedDescriptor) }
        try synchronize(descriptor: persistedDescriptor, path: destinationURL.path)
        try synchronizeDirectory(at: directoryURL)
    }

    static func synchronizeDirectory(at directoryURL: URL) throws {
        let descriptor = systemOpen(directoryURL.path, flags: O_RDONLY)
        guard descriptor >= 0 else {
            throw posixError(operation: "open directory", path: directoryURL.path)
        }
        defer { systemClose(descriptor) }
        try synchronize(descriptor: descriptor, path: directoryURL.path)
    }

    private static func synchronize(descriptor: Int32, path: String) throws {
        guard systemFsync(descriptor) == 0 else {
            throw posixError(operation: "fsync", path: path)
        }
    }

    private static func posixError(operation: String, path: String) -> PersistenceError {
        PersistenceError.io(operation: operation, path: path, errorCode: errno)
    }

    private static func systemOpen(_ path: String, flags: Int32) -> Int32 {
        path.withCString { pointer in
            #if canImport(Darwin)
            Darwin.open(pointer, flags)
            #else
            Glibc.open(pointer, flags)
            #endif
        }
    }

    private static func systemWrite(
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

    private static func systemFsync(_ descriptor: Int32) -> Int32 {
        #if canImport(Darwin)
        Darwin.fsync(descriptor)
        #else
        Glibc.fsync(descriptor)
        #endif
    }

    private static func systemClose(_ descriptor: Int32) {
        #if canImport(Darwin)
        _ = Darwin.close(descriptor)
        #else
        _ = Glibc.close(descriptor)
        #endif
    }

    private static func systemRename(from source: String, to destination: String) -> Int32 {
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
