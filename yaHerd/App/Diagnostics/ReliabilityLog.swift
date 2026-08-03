import CoreData
import Foundation
import OSLog
import SwiftData

/// Centralized reliability logging for persistence, sharing sync, and user-visible failures.
enum ReliabilityLog {
    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "yaHerd"

    nonisolated static let persistence = Logger(subsystem: subsystem, category: "Persistence")
    nonisolated static let sync = Logger(subsystem: subsystem, category: "Sync")
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

    nonisolated static func syncEvent(_ operation: String, trigger: String? = nil, detail: String? = nil) {
        sync.notice(
            "operation=\(operation, privacy: .public) trigger=\(trigger ?? "n/a", privacy: .public) detail=\(detail ?? "", privacy: .public)"
        )
    }

    nonisolated static func syncFailure(_ operation: String, trigger: String? = nil, error: Error) {
        sync.error(
            "operation=\(operation, privacy: .public) trigger=\(trigger ?? "n/a", privacy: .public) failed error=\(String(describing: error), privacy: .public)"
        )
    }

    nonisolated static func userVisibleFailure(_ message: String, error: Error) {
        userVisibleError.error(
            "message=\(message, privacy: .public) error=\(String(describing: error), privacy: .public)"
        )
    }
}

enum PersistenceLog {
    @discardableResult
    nonisolated static func fetch<T>(_ operation: String, _ work: () throws -> T) rethrows -> T {
        try PerformanceLog.measure("SwiftData.fetch.\(operation)", work)
    }

    nonisolated static func save(_ context: ModelContext, operation: String) throws {
        do {
            let preparedSave = try CollaborationMutationPipeline.prepareForSave(
                in: context,
                operation: operation
            )
            try PerformanceLog.measure("SwiftData.save.\(operation)") {
                try context.save()
            }
            preparedSave.commitRegistryUpdates()
            ReliabilityLog.persistenceEvent(operation, detail: "SwiftData save completed")
        } catch {
            ReliabilityLog.persistenceFailure(operation, error: error)
            throw error
        }
    }

    nonisolated static func save(_ context: NSManagedObjectContext, operation: String) throws {
        do {
            try PerformanceLog.measure("CoreData.save.\(operation)") {
                try context.save()
            }
            ReliabilityLog.persistenceEvent(operation, detail: "Core Data save completed")
        } catch {
            ReliabilityLog.persistenceFailure(operation, error: error)
            throw error
        }
    }

    nonisolated static func decodeFailure(_ operation: String, error: Error) {
        ReliabilityLog.persistenceFailure(operation, error: error)
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

    static func importFailed(_ error: Error) -> String {
        make(error, context: "Shared-data import failed")
    }

    static func syncFailed(_ error: Error) -> String {
        make(error, context: "Shared-data sync failed")
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
