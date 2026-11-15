import Foundation
import OSLog

/// Centralized reliability logging for persistence and user-visible failures.
enum ReliabilityLog {
    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "yaHerd"

    nonisolated static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    nonisolated static let userVisibleError = Logger(subsystem: subsystem, category: "UserVisibleError")

    nonisolated static func persistenceEvent(_ operation: String, detail: String? = nil) {
        if let detail {
            persistence.notice("operation=\(operation, privacy: .public) detail=\(detail, privacy: .public)")
        } else {
            persistence.notice("operation=\(operation, privacy: .public)")
        }
    }

    nonisolated static func persistenceFailure(_ operation: String, error: Error) {
        persistence.error(
            "operation=\(operation, privacy: .public) failed error=\(String(describing: error), privacy: .public)"
        )
    }

    /// Preserve the original Core Data error before repositories wrap it in a
    /// user-facing saveFailed message. The message alone loses the NSError
    /// domain, code, nested error and failing file required to diagnose a
    /// permission-denied SQLite write. File paths and raw details are private.
    nonisolated static func persistenceSaveFailure(_ operation: String, error: Error) {
        let failure = error as NSError
        let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError
        let path = (failure.userInfo[NSFilePathErrorKey] as? String)
            ?? (underlying?.userInfo[NSFilePathErrorKey] as? String)
        let fileName = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "unspecified"
        let underlyingDomain = underlying?.domain ?? "none"
        let underlyingCode = underlying?.code ?? -1

        persistence.error(
            "operation=\(operation, privacy: .public) save_failed domain=\(failure.domain, privacy: .public) code=\(failure.code) underlying_domain=\(underlyingDomain, privacy: .public) underlying_code=\(underlyingCode) file=\(fileName, privacy: .private) details=\(String(reflecting: failure), privacy: .private)"
        )
    }

    nonisolated static func userVisibleFailure(_ message: String, error: Error) {
        userVisibleError.error(
            "message=\(message, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }
}

enum UserVisibleErrorMessage {
    static func make(_ error: Error, context: String? = nil) -> String {
        let baseMessage = localizedMessage(for: error)
        if let context, !context.isEmpty {
            let message = "\(context): \(baseMessage)"
            ReliabilityLog.userVisibleFailure(message, error: error)
            return message
        }
        ReliabilityLog.userVisibleFailure(baseMessage, error: error)
        return baseMessage
    }

    static func saveFailed(_ error: Error) -> String {
        make(error, context: "Save failed")
    }

    private static func localizedMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription,
           !errorDescription.isEmpty {
            return errorDescription
        }

        let localizedDescription = error.localizedDescription
        if !localizedDescription.isEmpty {
            return localizedDescription
        }

        return "An unexpected error occurred."
    }
}
