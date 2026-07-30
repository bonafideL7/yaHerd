import Foundation
import OSLog

enum PerformanceLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "yaHerd"
    private static let logger = Logger(
        subsystem: subsystem,
        category: "Performance"
    )
    private static let signposter = OSSignposter(
        subsystem: subsystem,
        category: "PointsOfInterest"
    )

    @discardableResult
    static func measure<T>(_ operation: String, _ work: () throws -> T) rethrows -> T {
        let startedAt = Date()
        let signpostID = signposter.makeSignpostID()

        return try signposter.withIntervalSignpost(
            "yaHerd Operation",
            id: signpostID,
            "Operation: \(operation, privacy: .public)"
        ) {
            do {
                let result = try work()
                logDuration(operation, startedAt: startedAt, failed: false)
                return result
            } catch {
                logDuration(operation, startedAt: startedAt, failed: true, error: error)
                throw error
            }
        }
    }

    @discardableResult
    static func measureAsync<T>(
        _ operation: String,
        _ work: () async throws -> T
    ) async rethrows -> T {
        let startedAt = Date()
        let signpostID = signposter.makeSignpostID()
        let intervalState = signposter.beginInterval(
            "yaHerd Async Operation",
            id: signpostID,
            "Operation: \(operation, privacy: .public)"
        )
        defer {
            signposter.endInterval("yaHerd Async Operation", intervalState)
        }

        do {
            let result = try await work()
            logDuration(operation, startedAt: startedAt, failed: false)
            return result
        } catch {
            logDuration(operation, startedAt: startedAt, failed: true, error: error)
            throw error
        }
    }

    static func logDuration(
        _ operation: String,
        startedAt: Date,
        failed: Bool = false,
        error: Error? = nil
    ) {
        let elapsedMilliseconds = Date().timeIntervalSince(startedAt) * 1_000
        let elapsedText = String(format: "%.1f", elapsedMilliseconds)

        if failed {
            let errorText = error.map { String(describing: $0) } ?? "unknown error"
            logger.error("\(operation, privacy: .public) failed in \(elapsedText, privacy: .public) ms: \(errorText, privacy: .public)")
        } else {
            logger.debug("\(operation, privacy: .public) completed in \(elapsedText, privacy: .public) ms")
        }
    }

    static func event(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}
