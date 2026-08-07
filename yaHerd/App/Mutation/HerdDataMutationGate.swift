import Foundation

enum PublicIDRepairBridgeIdentity: String, Codable, Equatable, Sendable {
    case localOnly
    case iCloud
}

enum PublicIDRepairBridgeLocationIdentity: String, Codable, Equatable, Sendable {
    case unspecified
    case bridgeRecordMissing
    case ownerPrivateStore
    case acceptedSharedStore
}

struct PublicIDRepairBridgeTargetIdentity: Codable, Equatable, Sendable {
    let herdPublicID: UUID
    let location: PublicIDRepairBridgeLocationIdentity
    let bridgeFingerprint: String?

    init(
        herdPublicID: UUID,
        location: PublicIDRepairBridgeLocationIdentity,
        bridgeFingerprint: String? = nil
    ) {
        self.herdPublicID = herdPublicID
        self.location = location
        self.bridgeFingerprint = bridgeFingerprint
    }
}

struct PublicIDRepairBridgePreparation: Codable, Equatable, Sendable {
    let identity: PublicIDRepairBridgeIdentity
    let targets: [PublicIDRepairBridgeTargetIdentity]

    init(
        identity: PublicIDRepairBridgeIdentity,
        targets: [PublicIDRepairBridgeTargetIdentity]
    ) {
        self.identity = identity
        var targetByHerdID: [UUID: PublicIDRepairBridgeTargetIdentity] = [:]
        for target in targets.sorted(by: Self.targetSort) where targetByHerdID[target.herdPublicID] == nil {
            targetByHerdID[target.herdPublicID] = target
        }
        self.targets = targetByHerdID.values.sorted(by: Self.targetSort)
    }

    init(identity: PublicIDRepairBridgeIdentity, herdPublicIDs: [UUID]) {
        self.init(
            identity: identity,
            targets: herdPublicIDs.map {
                PublicIDRepairBridgeTargetIdentity(
                    herdPublicID: $0,
                    location: .unspecified
                )
            }
        )
    }

    var herdPublicIDs: [UUID] { targets.map(\.herdPublicID) }

    var requiresConvergence: Bool {
        identity == .iCloud && !targets.isEmpty
    }

    private static func targetSort(
        _ lhs: PublicIDRepairBridgeTargetIdentity,
        _ rhs: PublicIDRepairBridgeTargetIdentity
    ) -> Bool {
        if lhs.herdPublicID != rhs.herdPublicID {
            return lhs.herdPublicID.uuidString < rhs.herdPublicID.uuidString
        }
        return lhs.location.rawValue < rhs.location.rawValue
    }
}

fileprivate struct PublicIDRepairPendingState: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Equatable, Sendable {
        case localCommitPending
        case bridgeConvergenceRequired
    }

    let phase: Phase
    let preparation: PublicIDRepairBridgePreparation
    let report: PublicIDRepairReport
    let resolutions: [PublicIDRepairReferenceResolution]
}

/// Excludes duplicate-ID maintenance and incomplete bridge convergence from normal writes.
@MainActor
final class HerdDataMutationGate {
    enum GateError: LocalizedError, Equatable {
        case publicIDRepairInProgress(reason: SharedDataMutationReason)
        case publicIDRepairBlocksSynchronization
        case bridgeConvergenceRequired(reason: SharedDataMutationReason?)
        case synchronizationInProgress
        case publicIDRepairAlreadyInProgress
        case repairJournalUnavailable(details: String)

        var errorDescription: String? {
            switch self {
            case .publicIDRepairInProgress(let reason):
                return "Duplicate public-ID repair is in progress. The \(reason.displayName) change was blocked until the repair finishes."
            case .publicIDRepairBlocksSynchronization:
                return "Duplicate public-ID repair is in progress. Shared-herd synchronization was blocked until the repair finishes."
            case .bridgeConvergenceRequired(let reason):
                if let reason {
                    return "The repaired public IDs have not been verified in the shared-data bridge. The \(reason.displayName) change remains blocked. Open Sync Diagnostics and finish public-ID repair convergence."
                }
                return "The repaired public IDs have not been verified in the shared-data bridge. Synchronization remains blocked. Open Sync Diagnostics and finish public-ID repair convergence."
            case .synchronizationInProgress:
                return "Shared-herd synchronization is currently importing or exporting data. Wait for synchronization to finish before repairing duplicate public IDs."
            case .publicIDRepairAlreadyInProgress:
                return "Duplicate public-ID repair is already running."
            case .repairJournalUnavailable(let details):
                return "The durable public-ID repair journal could not be read or written. Normal edits and synchronization remain blocked to protect shared data. \(details)"
            }
        }
    }

    private static let pendingRepairStateKey = "PublicIDRepair.PendingState.v2"
    private static let legacyPendingBridgeReportKey = "PublicIDRepair.PendingBridgeConvergenceReport.v1"
    private static let pendingRepairJournalFileName = "PublicIDRepairPendingState.v3.json"

    private var repairToken: UUID?
    private var synchronizationTokens: Set<UUID> = []
    private let defaults: UserDefaults
    private let journal: PublicIDRepairDurableJournal
    private var pendingRepairState: PublicIDRepairPendingState?
    private var journalFailureDescription: String?

    init(
        defaults: UserDefaults = .standard,
        journalFileURL: URL? = nil
    ) {
        self.defaults = defaults
        self.journal = PublicIDRepairDurableJournal(
            fileURL: journalFileURL ?? Self.defaultJournalURL(defaults: defaults)
        )

        do {
            if let data = try journal.read() {
                pendingRepairState = try JSONDecoder().decode(
                    PublicIDRepairPendingState.self,
                    from: data
                )
                return
            }
        } catch {
            journalFailureDescription = error.localizedDescription
            return
        }

        if let data = defaults.data(forKey: Self.pendingRepairStateKey),
           let state = try? JSONDecoder().decode(PublicIDRepairPendingState.self, from: data) {
            pendingRepairState = state
            migrateLegacyStateToJournal(state)
        } else if let data = defaults.data(forKey: Self.legacyPendingBridgeReportKey),
                  let report = try? JSONDecoder().decode(PublicIDRepairReport.self, from: data) {
            let state = PublicIDRepairPendingState(
                phase: .bridgeConvergenceRequired,
                preparation: PublicIDRepairBridgePreparation(
                    identity: .iCloud,
                    herdPublicIDs: []
                ),
                report: report,
                resolutions: []
            )
            pendingRepairState = state
            migrateLegacyStateToJournal(state)
        }
    }

    var isPublicIDRepairInProgress: Bool { repairToken != nil }
    var isSynchronizing: Bool { !synchronizationTokens.isEmpty }
    var requiresBridgeConvergence: Bool {
        pendingRepairState != nil || journalFailureDescription != nil
    }
    var pendingBridgeConvergenceReport: PublicIDRepairReport? { pendingRepairState?.report }

    func validateLocalMutationAllowed(reason: SharedDataMutationReason) throws {
        try validateJournalAvailable()
        guard repairToken == nil else {
            throw GateError.publicIDRepairInProgress(reason: reason)
        }
        guard pendingRepairState == nil else {
            throw GateError.bridgeConvergenceRequired(reason: reason)
        }
    }

    func validateSyncDataResetAllowed() throws {
        try validateJournalAvailable()
        guard repairToken == nil else {
            throw GateError.publicIDRepairBlocksSynchronization
        }
        guard pendingRepairState == nil else {
            throw GateError.bridgeConvergenceRequired(reason: nil)
        }
        guard synchronizationTokens.isEmpty else {
            throw GateError.synchronizationInProgress
        }
    }

    func beginSynchronization() throws -> UUID {
        try validateJournalAvailable()
        guard repairToken == nil else {
            throw GateError.publicIDRepairBlocksSynchronization
        }
        guard pendingRepairState == nil else {
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
        try validateJournalAvailable()
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

    fileprivate var pendingState: PublicIDRepairPendingState? {
        pendingRepairState
    }

    func requireLocalCommitCompletion(
        preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport,
        resolutions: [PublicIDRepairReferenceResolution]
    ) throws {
        guard preparation.requiresConvergence else { return }
        try setPendingState(
            PublicIDRepairPendingState(
                phase: .localCommitPending,
                preparation: preparation,
                report: report,
                resolutions: resolutions
            )
        )
    }

    func markLocalCommitSucceeded() throws {
        guard let state = pendingRepairState else { return }
        guard state.phase == .localCommitPending else { return }
        try setPendingState(
            PublicIDRepairPendingState(
                phase: .bridgeConvergenceRequired,
                preparation: state.preparation,
                report: state.report,
                resolutions: state.resolutions
            )
        )
    }

    func clearPendingLocalCommitAfterRollback() {
        guard pendingRepairState?.phase == .localCommitPending else { return }
        do {
            try clearPendingState()
        } catch {
            journalFailureDescription = error.localizedDescription
        }
    }

    func completeBridgeConvergence() throws {
        try clearPendingState()
    }

    private func setPendingState(_ state: PublicIDRepairPendingState) throws {
        try persist(state)
        pendingRepairState = state
        journalFailureDescription = nil
    }

    private func persist(_ state: PublicIDRepairPendingState) throws {
        let data = try JSONEncoder().encode(state)
        try journal.persist(data)
        defaults.removeObject(forKey: Self.pendingRepairStateKey)
        defaults.removeObject(forKey: Self.legacyPendingBridgeReportKey)
    }

    private func clearPendingState() throws {
        try journal.remove()
        defaults.removeObject(forKey: Self.pendingRepairStateKey)
        defaults.removeObject(forKey: Self.legacyPendingBridgeReportKey)
        pendingRepairState = nil
        journalFailureDescription = nil
    }

    private func migrateLegacyStateToJournal(_ state: PublicIDRepairPendingState) {
        do {
            try persist(state)
        } catch {
            journalFailureDescription = error.localizedDescription
        }
    }

    private func validateJournalAvailable() throws {
        if let journalFailureDescription {
            throw GateError.repairJournalUnavailable(details: journalFailureDescription)
        }
    }

    private static func defaultJournalURL(defaults: UserDefaults) -> URL {
        #if DEBUG
        if defaults !== UserDefaults.standard {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("yaHerd-PublicIDRepairTests", isDirectory: true)
                .appendingPathComponent(
                    "\(ObjectIdentifier(defaults).hashValue)-\(pendingRepairJournalFileName)"
                )
        }
        #endif

        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("yaHerd", isDirectory: true)
            .appendingPathComponent("PublicIDRepair", isDirectory: true)
            .appendingPathComponent(pendingRepairJournalFileName)
    }
}

@MainActor
protocol PublicIDRepairBridgeCoordinating: AnyObject, Sendable {
    var bridgeIdentity: PublicIDRepairBridgeIdentity { get }
    func prepareForRepair() async throws -> PublicIDRepairBridgePreparation
    func convergeAfterRepair(
        preparation: PublicIDRepairBridgePreparation
    ) async throws
}

@MainActor
final class LocalOnlyPublicIDRepairBridgeCoordinator: PublicIDRepairBridgeCoordinating {
    let bridgeIdentity: PublicIDRepairBridgeIdentity = .localOnly

    func prepareForRepair() async throws -> PublicIDRepairBridgePreparation {
        PublicIDRepairBridgePreparation(identity: .localOnly, herdPublicIDs: [])
    }

    func convergeAfterRepair(
        preparation: PublicIDRepairBridgePreparation
    ) async throws {
        guard preparation.identity == .localOnly else {
            throw PublicIDRepairBridgeError.bridgeIdentityMismatch(
                expected: preparation.identity,
                actual: bridgeIdentity
            )
        }
    }
}

enum CoordinatedPublicIDRepairError: LocalizedError, Equatable {
    case localCommitStateIndeterminate

    var errorDescription: String? {
        switch self {
        case .localCommitStateIndeterminate:
            "yaHerd cannot prove whether the journaled public-ID repair transaction committed. Normal edits and synchronization remain blocked. Restore the repair backup or retry after the local store state is recovered."
        }
    }
}

@MainActor
final class CoordinatedPublicIDRepairService: PublicIDRepairService {
    private let worker: any PublicIDRepairTransactionalService
    private let mutationGate: HerdDataMutationGate
    private let bridgeCoordinator: any PublicIDRepairBridgeCoordinating

    init(
        worker: any PublicIDRepairTransactionalService,
        mutationGate: HerdDataMutationGate,
        bridgeCoordinator: any PublicIDRepairBridgeCoordinating = LocalOnlyPublicIDRepairBridgeCoordinator()
    ) {
        self.worker = worker
        self.mutationGate = mutationGate
        self.bridgeCoordinator = bridgeCoordinator
    }

    func scan() async throws -> PublicIDRepairAssessment {
        let assessment = try await worker.scan()
        var unresolvedReferences = assessment.unresolvedReferences
        if let pending = mutationGate.pendingState,
           pending.phase == .localCommitPending {
            var persistedSelections: [String: String] = [:]
            for resolution in pending.resolutions {
                persistedSelections[resolution.unresolvedReferenceID]
                    = resolution.selectedCandidateStableRecordIdentifier
            }
            unresolvedReferences.removeAll { issue in
                guard let selected = persistedSelections[issue.id] else { return false }
                return issue.candidates.contains {
                    $0.stableRecordIdentifier == selected
                }
            }
        }
        return PublicIDRepairAssessment(
            scannedAt: assessment.scannedAt,
            entities: assessment.entities,
            unresolvedReferences: unresolvedReferences,
            requiresBridgeConvergence: mutationGate.requiresBridgeConvergence
        )
    }

    func repair(
        resolutions: [PublicIDRepairReferenceResolution]
    ) async throws -> PublicIDRepairReport {
        let token = try mutationGate.beginPublicIDRepair()
        defer { mutationGate.endPublicIDRepair(token) }

        if let pending = mutationGate.pendingState {
            return try await resumePendingRepair(pending)
        }

        let preparation = try await bridgeCoordinator.prepareForRepair()
        guard preparation.requiresConvergence else {
            return try await worker.repair(resolutions: resolutions)
        }

        let report: PublicIDRepairReport
        do {
            report = try await worker.repair(
                resolutions: resolutions,
                willCommit: { [mutationGate] plannedReport in
                    try mutationGate.requireLocalCommitCompletion(
                        preparation: preparation,
                        report: plannedReport,
                        resolutions: resolutions
                    )
                }
            )
        } catch {
            mutationGate.clearPendingLocalCommitAfterRollback()
            throw error
        }

        try mutationGate.markLocalCommitSucceeded()
        try await bridgeCoordinator.convergeAfterRepair(preparation: preparation)
        try mutationGate.completeBridgeConvergence()
        return report
    }

    private func resumePendingRepair(
        _ pending: PublicIDRepairPendingState
    ) async throws -> PublicIDRepairReport {
        guard pending.preparation.identity == bridgeCoordinator.bridgeIdentity else {
            throw PublicIDRepairBridgeError.bridgeIdentityMismatch(
                expected: pending.preparation.identity,
                actual: bridgeCoordinator.bridgeIdentity
            )
        }

        var report = pending.report
        if pending.phase == .localCommitPending {
            switch try await worker.commitState(for: pending.report) {
            case .committed:
                try mutationGate.markLocalCommitSucceeded()
            case .notCommitted:
                do {
                    report = try await worker.repair(
                        resolutions: pending.resolutions,
                        willCommit: { [mutationGate] refreshedReport in
                            try mutationGate.requireLocalCommitCompletion(
                                preparation: pending.preparation,
                                report: refreshedReport,
                                resolutions: pending.resolutions
                            )
                        }
                    )
                    try mutationGate.markLocalCommitSucceeded()
                } catch {
                    let currentReport = mutationGate.pendingState?.report ?? pending.report
                    switch try await worker.commitState(for: currentReport) {
                    case .committed:
                        report = currentReport
                        try mutationGate.markLocalCommitSucceeded()
                    case .notCommitted:
                        mutationGate.clearPendingLocalCommitAfterRollback()
                        throw error
                    case .indeterminate:
                        throw CoordinatedPublicIDRepairError.localCommitStateIndeterminate
                    }
                }
            case .indeterminate:
                throw CoordinatedPublicIDRepairError.localCommitStateIndeterminate
            }
        }

        try await bridgeCoordinator.convergeAfterRepair(
            preparation: pending.preparation
        )
        try mutationGate.completeBridgeConvergence()
        return report
    }
}
