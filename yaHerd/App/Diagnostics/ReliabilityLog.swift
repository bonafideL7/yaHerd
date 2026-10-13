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
