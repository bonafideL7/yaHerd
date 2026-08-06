import Foundation

/// Excludes duplicate-ID maintenance and incomplete bridge convergence from normal writes.
@MainActor
final class HerdDataMutationGate {
    enum GateError: LocalizedError, Equatable {
        case publicIDRepairInProgress(reason: SharedDataMutationReason)
        case publicIDRepairBlocksSynchronization
        case bridgeConvergenceRequired(reason: SharedDataMutationReason?)
        case synchronizationInProgress
        case publicIDRepairAlreadyInProgress

        var errorDescription: String? {
            switch self {
            case .publicIDRepairInProgress(let reason):
                "Duplicate public-ID repair is in progress. The \(reason.displayName) change was blocked until the repair finishes."
            case .publicIDRepairBlocksSynchronization:
                "Duplicate public-ID repair is in progress. Shared-herd synchronization was blocked until the repair finishes."
            case .bridgeConvergenceRequired(let reason):
                if let reason {
                    return "The repaired public IDs have not been verified in the shared-data bridge. The \(reason.displayName) change remains blocked. Open Sync Diagnostics and finish public-ID repair convergence."
                }
                return "The repaired public IDs have not been verified in the shared-data bridge. Synchronization remains blocked. Open Sync Diagnostics and finish public-ID repair convergence."
            case .synchronizationInProgress:
                "Shared-herd synchronization is currently importing or exporting data. Wait for synchronization to finish before repairing duplicate public IDs."
            case .publicIDRepairAlreadyInProgress:
                "Duplicate public-ID repair is already running."
            }
        }
    }

    private static let pendingBridgeReportKey = "PublicIDRepair.PendingBridgeConvergenceReport.v1"

    private var repairToken: UUID?
    private var synchronizationTokens: Set<UUID> = []
    private let defaults: UserDefaults
    private var pendingBridgeReport: PublicIDRepairReport?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.pendingBridgeReportKey) {
            pendingBridgeReport = try? JSONDecoder().decode(PublicIDRepairReport.self, from: data)
        }
    }

    var isPublicIDRepairInProgress: Bool { repairToken != nil }
    var isSynchronizing: Bool { !synchronizationTokens.isEmpty }
    var requiresBridgeConvergence: Bool { pendingBridgeReport != nil }
    var pendingBridgeConvergenceReport: PublicIDRepairReport? { pendingBridgeReport }

    func validateLocalMutationAllowed(reason: SharedDataMutationReason) throws {
        guard repairToken == nil else {
            throw GateError.publicIDRepairInProgress(reason: reason)
        }
        guard pendingBridgeReport == nil else {
            throw GateError.bridgeConvergenceRequired(reason: reason)
        }
    }

    func beginSynchronization() throws -> UUID {
        guard repairToken == nil else {
            throw GateError.publicIDRepairBlocksSynchronization
        }
        guard pendingBridgeReport == nil else {
            throw GateError.bridgeConvergenceRequired(reason: nil)
        }
        let token = UUID()
        synchronizationTokens.insert(token)
        return token
    }

    func endSynchronization(_ token: UUID) {
        synchronizationTokens.remove(token)
    }

    func beginPublicIDRepair() throws -> UUID {
        guard repairToken == nil else {
            throw GateError.publicIDRepairAlreadyInProgress
        }
        guard synchronizationTokens.isEmpty else {
            throw GateError.synchronizationInProgress
        }
        let token = UUID()
        repairToken = token
        return token
    }

    func endPublicIDRepair(_ token: UUID) {
        guard repairToken == token else { return }
        repairToken = nil
    }

    func requireBridgeConvergence(for report: PublicIDRepairReport) throws {
        let data = try JSONEncoder().encode(report)
        defaults.set(data, forKey: Self.pendingBridgeReportKey)
        pendingBridgeReport = report
    }

    func completeBridgeConvergence() {
        defaults.removeObject(forKey: Self.pendingBridgeReportKey)
        pendingBridgeReport = nil
    }
}

@MainActor
protocol PublicIDRepairBridgeCoordinating: AnyObject {
    /// Imports the current bridge state and verifies that this device can write the repaired graph.
    /// Returns true when export-only convergence is required after SwiftData repair.
    func prepareForRepair() async throws -> Bool

    /// Exports the repaired SwiftData graph without importing the stale bridge first, then validates it.
    func convergeAfterRepair() async throws
}

@MainActor
final class LocalOnlyPublicIDRepairBridgeCoordinator: PublicIDRepairBridgeCoordinating {
    func prepareForRepair() async throws -> Bool { false }
    func convergeAfterRepair() async throws {}
}

@MainActor
final class CoordinatedPublicIDRepairService: PublicIDRepairService {
    private let worker: any PublicIDRepairService
    private let mutationGate: HerdDataMutationGate
    private let bridgeCoordinator: any PublicIDRepairBridgeCoordinating

    init(
        worker: any PublicIDRepairService,
        mutationGate: HerdDataMutationGate,
        bridgeCoordinator: any PublicIDRepairBridgeCoordinating = LocalOnlyPublicIDRepairBridgeCoordinator()
    ) {
        self.worker = worker
        self.mutationGate = mutationGate
        self.bridgeCoordinator = bridgeCoordinator
    }

    func scan() async throws -> PublicIDRepairAssessment {
        let assessment = try await worker.scan()
        return PublicIDRepairAssessment(
            scannedAt: assessment.scannedAt,
            entities: assessment.entities,
            unresolvedReferences: assessment.unresolvedReferences,
            requiresBridgeConvergence: mutationGate.requiresBridgeConvergence
        )
    }

    func repair(
        resolutions: [PublicIDRepairReferenceResolution]
    ) async throws -> PublicIDRepairReport {
        let token = try mutationGate.beginPublicIDRepair()
        defer { mutationGate.endPublicIDRepair(token) }

        if let pendingReport = mutationGate.pendingBridgeConvergenceReport {
            try await bridgeCoordinator.convergeAfterRepair()
            mutationGate.completeBridgeConvergence()
            return pendingReport
        }

        let requiresBridgeConvergence = try await bridgeCoordinator.prepareForRepair()
        let report = try await worker.repair(resolutions: resolutions)
        guard requiresBridgeConvergence else { return report }

        // Persist this before bridge work so a failure or process termination cannot release
        // normal writes/sync into an import-first path that still contains obsolete IDs.
        try mutationGate.requireBridgeConvergence(for: report)
        try await bridgeCoordinator.convergeAfterRepair()
        mutationGate.completeBridgeConvergence()
        return report
    }
}
