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
        for target in targets.sorted(by: Self.targetSort)
        where targetByHerdID[target.herdPublicID] == nil {
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
    let bridgeIssues: [PublicIDRepairUnresolvedReference]?
    /// Present only while a second local repair is being committed under an already committed,
    /// still-gated repair transaction. It is restored if the chained save rolls back and merged
    /// into `report` only after that chained save is proven committed.
    let committedReport: PublicIDRepairReport?

    init(
        phase: Phase,
        preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport,
        resolutions: [PublicIDRepairReferenceResolution],
        bridgeIssues: [PublicIDRepairUnresolvedReference]? = nil,
        committedReport: PublicIDRepairReport? = nil
    ) {
        self.phase = phase
        self.preparation = preparation
        self.report = report
        self.resolutions = resolutions
        self.bridgeIssues = bridgeIssues
        self.committedReport = committedReport
    }
}

/// Excludes duplicate-ID maintenance, destructive reset, and incomplete bridge convergence from normal writes.
@MainActor
final class HerdDataMutationGate {
    enum GateError: LocalizedError, Equatable {
        case publicIDRepairInProgress(reason: SharedDataMutationReason)
        case publicIDRepairBlocksSynchronization
        case bridgeConvergenceRequired(reason: SharedDataMutationReason?)
        case synchronizationInProgress
        case publicIDRepairAlreadyInProgress
        case syncDataResetInProgress(reason: SharedDataMutationReason?)
        case syncDataResetAlreadyInProgress
        case repairJournalUnavailable(details: String)
        case bridgeResolutionSelectionIncomplete
        case bridgeResolutionConflictsWithEstablishedOwner

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
                return "Shared-herd synchronization is currently importing or exporting data. Wait for synchronization to finish before repairing duplicate public IDs or resetting iCloud sync data."
            case .publicIDRepairAlreadyInProgress:
                return "Duplicate public-ID repair is already running."
            case .syncDataResetInProgress(let reason):
                if let reason {
                    return "iCloud sync data is being reset. The \(reason.displayName) change was blocked until the reset finishes."
                }
                return "iCloud sync data is being reset. Synchronization and duplicate public-ID repair are blocked until the reset finishes."
            case .syncDataResetAlreadyInProgress:
                return "iCloud sync data is already being reset."
            case .repairJournalUnavailable(let details):
                return "The durable public-ID repair journal could not be read or written. Normal edits and synchronization remain blocked to protect shared data. Open Sync Diagnostics and choose Finish Shared-Data Convergence to recover the journal when a verified recovery copy is available. \(details)"
            case .bridgeResolutionSelectionIncomplete:
                return "Every shared-data repair choice must be selected in Sync Diagnostics before convergence can continue."
            case .bridgeResolutionConflictsWithEstablishedOwner:
                return "This shared public ID already has a durable repair owner. The established owner cannot be replaced by a later conflicting choice."
            }
        }
    }

    private static let pendingRepairStateKey = "PublicIDRepair.PendingState.v2"
    private static let legacyPendingBridgeReportKey = "PublicIDRepair.PendingBridgeConvergenceReport.v1"
    private static let pendingRepairJournalFileName = "PublicIDRepairPendingState.v3.json"

    private var repairToken: UUID?
    private var synchronizationTokens: Set<UUID> = []
    private var syncDataResetToken: UUID?
    private let defaults: UserDefaults
    private let journal: PublicIDRepairDurableJournal
    private let verifiedRecoveryJournal: PublicIDRepairDurableJournal
    private var pendingRepairState: PublicIDRepairPendingState?
    private var recoverablePendingRepairState: PublicIDRepairPendingState?
    private var journalFailureDescription: String?

    init(
        defaults: UserDefaults = .standard,
        journalFileURL: URL? = nil
    ) {
        self.defaults = defaults
        let resolvedJournalURL = journalFileURL ?? Self.defaultJournalURL(defaults: defaults)
        journal = PublicIDRepairDurableJournal(fileURL: resolvedJournalURL)
        verifiedRecoveryJournal = PublicIDRepairDurableJournal(
            fileURL: resolvedJournalURL.appendingPathExtension("verified-recovery")
        )

        let verifiedRecoveryState = Self.readPendingState(from: verifiedRecoveryJournal)
        do {
            if let data = try journal.read() {
                let activeState = try JSONDecoder().decode(PublicIDRepairPendingState.self, from: data)
                if let verifiedRecoveryState, verifiedRecoveryState != activeState {
                    recoverablePendingRepairState = verifiedRecoveryState
                    journalFailureDescription = "The active public-ID repair journal disagrees with the verified pre-commit recovery transaction. The verified recovery state must be restored before convergence continues."
                    return
                }
                pendingRepairState = activeState
                if verifiedRecoveryState == nil {
                    try? verifiedRecoveryJournal.persist(data)
                }
                return
            }
        } catch {
            let primaryFailure = error.localizedDescription
            if let verifiedRecoveryState {
                recoverablePendingRepairState = verifiedRecoveryState
                journalFailureDescription = primaryFailure
            } else {
                journalFailureDescription = primaryFailure
            }
            return
        }

        if let verifiedRecoveryState {
            recoverablePendingRepairState = verifiedRecoveryState
            journalFailureDescription = "The active public-ID repair journal is missing while a verified recovery transaction remains available."
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
    var isSyncDataResetInProgress: Bool { syncDataResetToken != nil }
    var requiresBridgeConvergence: Bool {
        pendingRepairState != nil
            || recoverablePendingRepairState != nil
            || journalFailureDescription != nil
    }
    var pendingBridgeConvergenceReport: PublicIDRepairReport? {
        guard let state = recoverablePendingRepairState ?? pendingRepairState else { return nil }
        return Self.mergedReport(
            committed: state.committedReport,
            latest: state.report
        )
    }

    func validateLocalMutationAllowed(reason: SharedDataMutationReason) throws {
        try validateJournalAvailable()
        guard repairToken == nil else {
            throw GateError.publicIDRepairInProgress(reason: reason)
        }
        guard pendingRepairState == nil else {
            throw GateError.bridgeConvergenceRequired(reason: reason)
        }
        guard syncDataResetToken == nil else {
            throw GateError.syncDataResetInProgress(reason: reason)
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
        guard syncDataResetToken == nil else {
            throw GateError.syncDataResetInProgress(reason: nil)
        }
        let token = UUID()
        synchronizationTokens.insert(token)
        return token
    }

    func endSynchronization(_ token: UUID) {
        synchronizationTokens.remove(token)
    }

    func beginPublicIDRepair() throws -> UUID {
        if journalFailureDescription != nil {
            try recoverUnavailableJournalForDiagnostics()
        }
        try validateJournalAvailable()
        guard repairToken == nil else {
            throw GateError.publicIDRepairAlreadyInProgress
        }
        guard synchronizationTokens.isEmpty else {
            throw GateError.synchronizationInProgress
        }
        guard syncDataResetToken == nil else {
            throw GateError.syncDataResetInProgress(reason: nil)
        }
        let token = UUID()
        repairToken = token
        return token
    }

    func endPublicIDRepair(_ token: UUID) {
        guard repairToken == token else { return }
        repairToken = nil
    }

    func beginSyncDataReset() throws -> UUID {
        try validateJournalAvailable()
        guard pendingRepairState == nil else {
            throw GateError.bridgeConvergenceRequired(reason: nil)
        }
        guard repairToken == nil else {
            throw GateError.publicIDRepairBlocksSynchronization
        }
        guard synchronizationTokens.isEmpty else {
            throw GateError.synchronizationInProgress
        }
        guard syncDataResetToken == nil else {
            throw GateError.syncDataResetAlreadyInProgress
        }
        let token = UUID()
        syncDataResetToken = token
        return token
    }

    func endSyncDataReset(_ token: UUID) {
        guard syncDataResetToken == token else { return }
        syncDataResetToken = nil
    }

    fileprivate var pendingState: PublicIDRepairPendingState? {
        recoverablePendingRepairState ?? pendingRepairState
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

    func requireChainedLocalCommitCompletion(
        preparation: PublicIDRepairBridgePreparation,
        committedReport: PublicIDRepairReport,
        report: PublicIDRepairReport,
        resolutions: [PublicIDRepairReferenceResolution]
    ) throws {
        try setPendingState(
            PublicIDRepairPendingState(
                phase: .localCommitPending,
                preparation: preparation,
                report: report,
                resolutions: resolutions,
                committedReport: committedReport
            )
        )
    }

    func markLocalCommitSucceeded() throws {
        guard let state = pendingRepairState,
              state.phase == .localCommitPending else { return }
        let committedReport = Self.mergedReport(
            committed: state.committedReport,
            latest: state.report
        )
        try setPendingState(
            PublicIDRepairPendingState(
                phase: .bridgeConvergenceRequired,
                preparation: state.preparation,
                report: committedReport,
                resolutions: state.resolutions,
                bridgeIssues: state.bridgeIssues
            )
        )
    }

    func updatePendingPreparation(
        _ preparation: PublicIDRepairBridgePreparation
    ) throws {
        guard let state = pendingRepairState,
              state.preparation != preparation else {
            return
        }
        try setPendingState(
            PublicIDRepairPendingState(
                phase: state.phase,
                preparation: preparation,
                report: state.report,
                resolutions: state.resolutions,
                bridgeIssues: state.bridgeIssues,
                committedReport: state.committedReport
            )
        )
    }

    func recordBridgeResolutionIssues(
        _ issues: [PublicIDRepairUnresolvedReference]
    ) throws {
        guard let state = pendingRepairState else { return }
        try setPendingState(
            PublicIDRepairPendingState(
                phase: state.phase,
                preparation: state.preparation,
                report: state.report,
                resolutions: state.resolutions,
                bridgeIssues: issues.sorted { $0.id < $1.id },
                committedReport: state.committedReport
            )
        )
    }

    func applyBridgeResolutionSelections(
        _ resolutions: [PublicIDRepairReferenceResolution]
    ) throws {
        guard let state = pendingRepairState,
              let issues = state.bridgeIssues,
              !issues.isEmpty else {
            return
        }

        let selectionByIssueID = Dictionary(
            uniqueKeysWithValues: resolutions.map {
                ($0.unresolvedReferenceID, $0.selectedCandidateStableRecordIdentifier)
            }
        )
        var selectedBridgeUpdates: [PublicIDRepairReferenceUpdate] = []
        var selectedCollisionResolutions: [PublicIDRepairBridgeCollisionResolution] = []
        var selectedRecoveryActions: [PublicIDRepairBridgeRecoveryAction] = []
        let establishedCollisionResolutions = state.report.bridgeCollisionResolutions ?? []

        for issue in issues {
            guard let selectedStableID = selectionByIssueID[issue.id],
                  let candidate = issue.candidates.first(where: {
                      $0.stableRecordIdentifier == selectedStableID
                  }) else {
                throw GateError.bridgeResolutionSelectionIncomplete
            }

            switch issue.kind {
            case .bridgeRecordOwner:
                let resolutionID = "\(issue.entityType.rawValue)|\(issue.referencedPublicID.uuidString.lowercased())"
                let existing = establishedCollisionResolutions.first { $0.id == resolutionID }
                if let existing,
                   existing.selectedHerdPublicID != candidate.resultingPublicID {
                    throw GateError.bridgeResolutionConflictsWithEstablishedOwner
                }
                let provenParticipantHerdIDs = issue.bridgeParticipantHerdPublicIDs
                    ?? issue.candidates.map(\.resultingPublicID)
                let herdPublicIDs = Set(existing?.herdPublicIDs ?? [])
                    .union(provenParticipantHerdIDs)
                    .union([candidate.resultingPublicID])
                selectedCollisionResolutions.append(
                    PublicIDRepairBridgeCollisionResolution(
                        entityType: issue.entityType,
                        retainedPublicID: issue.referencedPublicID,
                        selectedHerdPublicID: existing?.selectedHerdPublicID
                            ?? candidate.resultingPublicID,
                        herdPublicIDs: Array(herdPublicIDs),
                        replacementMappings: existing?.replacementMappings
                    )
                )

            case .preparedHerdRecovery:
                guard candidate.resultingPublicID == issue.referencedPublicID else {
                    throw GateError.bridgeResolutionSelectionIncomplete
                }
                let kind: PublicIDRepairBridgeRecoveryActionKind
                if selectedStableID.hasPrefix("restore-prepared-herd|") {
                    kind = .restoreMissingPreparedHerd
                } else if selectedStableID.hasPrefix("retire-prepared-herd|") {
                    kind = .retireIntentionallyDeletedPreparedHerd
                } else {
                    // Legacy one-action recovery does not prove current user intent. Require a new
                    // scan so Diagnostics presents the two explicit terminal decisions.
                    throw GateError.bridgeResolutionSelectionIncomplete
                }
                selectedRecoveryActions.append(
                    PublicIDRepairBridgeRecoveryAction(
                        kind: kind,
                        herdPublicID: issue.referencedPublicID
                    )
                )

            case .indeterminateLocalRepairRecovery:
                // Local recovery selections are interpreted by the coordinated service against
                // the exact pending manifest generation. They are not bridge decisions.
                continue

            case .lookupReference, .treatmentReference, .canonicalRecord:
                selectedBridgeUpdates.append(
                    PublicIDRepairReferenceUpdate(
                        entityType: issue.entityType,
                        recordDescription: issue.recordDescription,
                        stableRecordIdentifier: issue.stableRecordIdentifier,
                        fieldName: issue.fieldName,
                        previousPublicID: issue.referencedPublicID,
                        repairedPublicID: candidate.resultingPublicID
                    )
                )
            }
        }

        let updatedManifest = state.report.manifest.appendingBridgeDecisions(
            completedAt: .now,
            collisionResolutions: selectedCollisionResolutions,
            referenceUpdates: selectedBridgeUpdates,
            recoveryActions: selectedRecoveryActions
        )
        let priorBackups = updatedManifest.backupReferences.filter {
            $0.path != state.report.backupPath
        }
        let updatedReport = PublicIDRepairReport(
            completedAt: .now,
            assessment: state.report.assessment,
            replacements: [],
            referenceUpdates: [],
            backupFilename: state.report.backupFilename,
            backupPath: state.report.backupPath,
            validationIssueCount: state.report.validationIssueCount,
            priorBackups: priorBackups.isEmpty ? nil : priorBackups,
            manifest: updatedManifest
        )
        try setPendingState(
            PublicIDRepairPendingState(
                phase: state.phase,
                preparation: state.preparation,
                report: updatedReport,
                resolutions: state.resolutions,
                bridgeIssues: nil,
                committedReport: state.committedReport
            )
        )
    }

    func clearPendingLocalCommitAfterRollback() {
        let state = recoverablePendingRepairState ?? pendingRepairState
        guard let state, state.phase == .localCommitPending else { return }
        do {
            if let committedReport = state.committedReport {
                try setPendingState(
                    PublicIDRepairPendingState(
                        phase: .bridgeConvergenceRequired,
                        preparation: state.preparation,
                        report: committedReport,
                        resolutions: state.resolutions
                    )
                )
            } else {
                try clearPendingState()
            }
        } catch {
            journalFailureDescription = error.localizedDescription
        }
    }

    func completeBridgeConvergence() throws {
        try clearPendingState()
    }

    private func setPendingState(_ state: PublicIDRepairPendingState) throws {
        do {
            try persist(state)
            pendingRepairState = state
            recoverablePendingRepairState = nil
            journalFailureDescription = nil
        } catch {
            recoverablePendingRepairState = state
            journalFailureDescription = error.localizedDescription
            throw error
        }
    }

    private func persist(_ state: PublicIDRepairPendingState) throws {
        let data = try JSONEncoder().encode(state)
        try verifiedRecoveryJournal.persist(data)
        try journal.persist(data)
        defaults.removeObject(forKey: Self.pendingRepairStateKey)
        defaults.removeObject(forKey: Self.legacyPendingBridgeReportKey)
    }

    private func clearPendingState() throws {
        try journal.remove()
        try verifiedRecoveryJournal.remove()
        defaults.removeObject(forKey: Self.pendingRepairStateKey)
        defaults.removeObject(forKey: Self.legacyPendingBridgeReportKey)
        pendingRepairState = nil
        recoverablePendingRepairState = nil
        journalFailureDescription = nil
    }

    private func migrateLegacyStateToJournal(_ state: PublicIDRepairPendingState) {
        do {
            try persist(state)
        } catch {
            recoverablePendingRepairState = state
            journalFailureDescription = error.localizedDescription
        }
    }

    private func recoverUnavailableJournalForDiagnostics() throws {
        guard journalFailureDescription != nil else { return }
        guard repairToken == nil else {
            throw GateError.publicIDRepairAlreadyInProgress
        }
        guard synchronizationTokens.isEmpty else {
            throw GateError.synchronizationInProgress
        }
        guard syncDataResetToken == nil else {
            throw GateError.syncDataResetInProgress(reason: nil)
        }
        guard let recovered = recoverablePendingRepairState else {
            try validateJournalAvailable()
            return
        }

        do {
            try persist(recovered)
            pendingRepairState = recovered
            recoverablePendingRepairState = nil
            journalFailureDescription = nil
        } catch {
            journalFailureDescription = error.localizedDescription
            throw GateError.repairJournalUnavailable(details: error.localizedDescription)
        }
    }

    private func validateJournalAvailable() throws {
        if let journalFailureDescription {
            throw GateError.repairJournalUnavailable(details: journalFailureDescription)
        }
    }

    private static func mergedReport(
        committed: PublicIDRepairReport?,
        latest: PublicIDRepairReport
    ) -> PublicIDRepairReport {
        guard let committed else { return latest }

        let mergedManifest = committed.manifest.appendingCommittedRepair(latest.manifest)
        let priorBackups = mergedManifest.backupReferences.filter {
            $0.path != latest.backupPath
        }
        return PublicIDRepairReport(
            completedAt: max(committed.completedAt, latest.completedAt),
            assessment: latest.assessment,
            replacements: [],
            referenceUpdates: [],
            backupFilename: latest.backupFilename,
            backupPath: latest.backupPath,
            validationIssueCount: committed.validationIssueCount + latest.validationIssueCount,
            priorBackups: priorBackups.isEmpty ? nil : priorBackups,
            manifest: mergedManifest
        )
    }

    private static func readPendingState(
        from journal: PublicIDRepairDurableJournal
    ) -> PublicIDRepairPendingState? {
        guard let data = try? journal.read() else { return nil }
        return try? JSONDecoder().decode(PublicIDRepairPendingState.self, from: data)
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
    func validateMutationAuthority(
        preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport
    ) async throws -> PublicIDRepairBridgePreparation
    func rebasePendingRepair(
        preparation: PublicIDRepairBridgePreparation
    ) async throws -> PublicIDRepairBridgePreparation
    func convergeAfterRepair(
        preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport
    ) async throws
}

extension PublicIDRepairBridgeCoordinating {
    func validateMutationAuthority(
        preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport
    ) async throws -> PublicIDRepairBridgePreparation {
        preparation
    }

    func rebasePendingRepair(
        preparation: PublicIDRepairBridgePreparation
    ) async throws -> PublicIDRepairBridgePreparation {
        preparation
    }
}

@MainActor
final class LocalOnlyPublicIDRepairBridgeCoordinator: PublicIDRepairBridgeCoordinating {
    let bridgeIdentity: PublicIDRepairBridgeIdentity = .localOnly

    func prepareForRepair() async throws -> PublicIDRepairBridgePreparation {
        PublicIDRepairBridgePreparation(identity: .localOnly, herdPublicIDs: [])
    }

    func convergeAfterRepair(
        preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport
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
    case localGraphChangedDuringRecovery

    var errorDescription: String? {
        switch self {
        case .localCommitStateIndeterminate:
            "yaHerd cannot yet prove whether the journaled public-ID repair transaction committed. Normal edits and synchronization remain blocked. Scan in Sync Diagnostics and use the manifest-guided recovery action shown there."
        case .localGraphChangedDuringRecovery:
            "The local synchronized graph kept changing while public-ID repair recovery was reconciling newly arrived duplicate data. Normal edits and synchronization remain blocked; run Sync Diagnostics again after iCloud changes settle."
        }
    }
}

private enum PublicIDRepairBridgeConvergenceOutcome {
    case converged(PublicIDRepairReport)
    case automaticResolutionApplied([PublicIDRepairUnresolvedReference])
}

@MainActor
final class CoordinatedPublicIDRepairService: PublicIDRepairService {
    private let worker: any PublicIDRepairTransactionalService
    private let mutationGate: HerdDataMutationGate
    private let bridgeCoordinator: any PublicIDRepairBridgeCoordinating
    private let maximumChainedRepairCount = 3

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
        if let pending = mutationGate.pendingState {
            if pending.phase == .localCommitPending {
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

                if try await worker.commitState(for: pending.report) == .indeterminate {
                    let recoveryAssessment = try await worker.assessIndeterminateRecovery(
                        for: pending.report
                    )
                    if recoveryAssessment.requiresManualResolution {
                        unresolvedReferences.append(
                            contentsOf: recoveryAssessment.manualResolutionIssues
                        )
                    } else {
                        unresolvedReferences.append(
                            Self.indeterminateRecoveryIssue(
                                report: pending.report,
                                assessment: recoveryAssessment
                            )
                        )
                    }
                }
            }
            unresolvedReferences.append(contentsOf: pending.bridgeIssues ?? [])
        }
        unresolvedReferences = Dictionary(
            grouping: unresolvedReferences,
            by: \.id
        ).compactMap { $0.value.first }
            .sorted { $0.id < $1.id }

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

        if mutationGate.pendingState != nil {
            try mutationGate.applyBridgeResolutionSelections(resolutions)
            guard let pending = mutationGate.pendingState else {
                throw CoordinatedPublicIDRepairError.localCommitStateIndeterminate
            }
            return try await resumePendingRepair(
                pending,
                requestedResolutions: resolutions
            )
        }

        let preparation = try await bridgeCoordinator.prepareForRepair()
        guard preparation.requiresConvergence else {
            return try await worker.repair(resolutions: resolutions)
        }

        do {
            _ = try await worker.repair(
                resolutions: resolutions,
                willCommit: { [mutationGate, bridgeCoordinator] plannedReport in
                    let plannedPreparation = Self.preparationForCommittedRepair(
                        preparation,
                        report: plannedReport
                    )
                    let authorizedPreparation = try await bridgeCoordinator.validateMutationAuthority(
                        preparation: plannedPreparation,
                        report: plannedReport
                    )
                    try mutationGate.requireLocalCommitCompletion(
                        preparation: authorizedPreparation,
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
        guard let pending = mutationGate.pendingState else {
            throw CoordinatedPublicIDRepairError.localCommitStateIndeterminate
        }
        return try await resumePendingRepair(
            pending,
            requestedResolutions: resolutions
        )
    }

    private func resumePendingRepair(
        _ pending: PublicIDRepairPendingState,
        requestedResolutions: [PublicIDRepairReferenceResolution]
    ) async throws -> PublicIDRepairReport {
        guard pending.preparation.identity == bridgeCoordinator.bridgeIdentity else {
            throw PublicIDRepairBridgeError.bridgeIdentityMismatch(
                expected: pending.preparation.identity,
                actual: bridgeCoordinator.bridgeIdentity
            )
        }

        let combinedResolutions = mergedResolutions(
            pending.resolutions,
            requestedResolutions
        )
        if pending.phase == .localCommitPending {
            try await recoverPendingLocalCommit(
                pending,
                resolutions: combinedResolutions
            )
        }

        var chainedRepairCount = 0
        var automaticallyResolvedBridgeIssueIDs: Set<String> = []
        while true {
            guard let currentState = mutationGate.pendingState else {
                throw CoordinatedPublicIDRepairError.localCommitStateIndeterminate
            }

            let assessment = try await worker.scan()
            let rebasedPreparation = try await bridgeCoordinator.rebasePendingRepair(
                preparation: currentState.preparation
            )
            try mutationGate.updatePendingPreparation(rebasedPreparation)
            guard let rebasedState = mutationGate.pendingState else {
                throw CoordinatedPublicIDRepairError.localCommitStateIndeterminate
            }

            let repairResolutions = workerResolutions(
                combinedResolutions,
                report: rebasedState.report
            )
            let shouldTryChainedRepair = assessment.hasDuplicates
                || !(rebasedState.report.bridgeCollisionResolutions ?? []).isEmpty
            if shouldTryChainedRepair {
                guard chainedRepairCount < maximumChainedRepairCount else {
                    throw CoordinatedPublicIDRepairError.localGraphChangedDuringRecovery
                }
                do {
                    let chainedReport = try await worker.repair(
                        resolutions: repairResolutions,
                        willCommit: { [mutationGate, bridgeCoordinator] plannedReport in
                            let authorizedPreparation = try await bridgeCoordinator.validateMutationAuthority(
                                preparation: rebasedPreparation,
                                report: plannedReport
                            )
                            try mutationGate.requireChainedLocalCommitCompletion(
                                preparation: authorizedPreparation,
                                committedReport: rebasedState.report,
                                report: plannedReport,
                                resolutions: repairResolutions
                            )
                        }
                    )
                    try mutationGate.markLocalCommitSucceeded()
                    chainedRepairCount += 1
                    if chainedReport.repairedRecordCount > 0
                        || chainedReport.updatedReferenceCount > 0 {
                        continue
                    }
                } catch PublicIDRepairError.noDuplicatesFound {
                    if assessment.hasDuplicates {
                        // The graph changed between scan and repair planning. Re-scan rather than
                        // converging against a stale uniqueness observation.
                        continue
                    }
                } catch {
                    mutationGate.clearPendingLocalCommitAfterRollback()
                    throw error
                }
            }

            guard let convergingState = mutationGate.pendingState else {
                throw CoordinatedPublicIDRepairError.localCommitStateIndeterminate
            }
            let finalPreparation = try await bridgeCoordinator.rebasePendingRepair(
                preparation: convergingState.preparation
            )
            try mutationGate.updatePendingPreparation(finalPreparation)
            guard let preparedState = mutationGate.pendingState else {
                throw CoordinatedPublicIDRepairError.localCommitStateIndeterminate
            }
            let convergencePreparation = Self.preparationForCommittedRepair(
                preparedState.preparation,
                report: preparedState.report
            )
            try mutationGate.updatePendingPreparation(convergencePreparation)
            guard let readyState = mutationGate.pendingState else {
                throw CoordinatedPublicIDRepairError.localCommitStateIndeterminate
            }

            switch try await convergeAfterRepair(
                preparation: convergencePreparation,
                report: readyState.report
            ) {
            case .automaticResolutionApplied(let issues):
                let issueIDs = Set(issues.map(\.id))
                guard !issueIDs.isSubset(of: automaticallyResolvedBridgeIssueIDs) else {
                    throw PublicIDRepairBridgeResolutionRequired(issues: issues)
                }
                automaticallyResolvedBridgeIssueIDs.formUnion(issueIDs)
                // The durable owner/mapping is now journaled. Return to the outer loop so local
                // SwiftData is repaired with that exact mapping before the bridge is retried.
                continue

            case .converged(let finalReport):
                // SwiftData's CloudKit mirroring is not controlled by the mutation gate. A remote
                // duplicate can therefore materialize while bridge convergence is awaiting I/O.
                // Prove local global uniqueness again before clearing the durable journal; if
                // repair work appeared, chain it under the same journal and reconverge.
                let postConvergenceAssessment = try await worker.scan()
                guard let postConvergenceState = mutationGate.pendingState else {
                    throw CoordinatedPublicIDRepairError.localCommitStateIndeterminate
                }
                let postConvergenceResolutions = workerResolutions(
                    combinedResolutions,
                    report: postConvergenceState.report
                )
                let shouldTryPostConvergenceRepair = postConvergenceAssessment.hasDuplicates
                if shouldTryPostConvergenceRepair {
                    guard chainedRepairCount < maximumChainedRepairCount else {
                        throw CoordinatedPublicIDRepairError.localGraphChangedDuringRecovery
                    }
                    do {
                        _ = try await worker.repair(
                            resolutions: postConvergenceResolutions,
                            willCommit: { [mutationGate, bridgeCoordinator] plannedReport in
                                let authorizedPreparation = try await bridgeCoordinator.validateMutationAuthority(
                                    preparation: convergencePreparation,
                                    report: plannedReport
                                )
                                try mutationGate.requireChainedLocalCommitCompletion(
                                    preparation: authorizedPreparation,
                                    committedReport: postConvergenceState.report,
                                    report: plannedReport,
                                    resolutions: postConvergenceResolutions
                                )
                            }
                        )
                        try mutationGate.markLocalCommitSucceeded()
                        chainedRepairCount += 1
                        // A successful chained repair changes the durable local repair generation.
                        // Bridge convergence must always be repeated against that exact generation,
                        // even when the report projects zero record/reference counters.
                        continue
                    } catch PublicIDRepairError.noDuplicatesFound {
                        if postConvergenceAssessment.hasDuplicates {
                            continue
                        }
                    } catch {
                        mutationGate.clearPendingLocalCommitAfterRollback()
                        throw error
                    }
                }

                try mutationGate.completeBridgeConvergence()
                return finalReport
            }
        }
    }

    private func recoverPendingLocalCommit(
        _ pending: PublicIDRepairPendingState,
        resolutions: [PublicIDRepairReferenceResolution]
    ) async throws {
        switch try await worker.commitState(for: pending.report) {
        case .committed:
            try mutationGate.markLocalCommitSucceeded()

        case .notCommitted:
            let recoveryReport = pending.committedReport ?? pending.report
            let recoveryResolutions = workerResolutions(
                resolutions,
                report: recoveryReport
            )
            do {
                _ = try await worker.repair(
                    resolutions: recoveryResolutions,
                    willCommit: { [mutationGate, bridgeCoordinator] refreshedReport in
                        let prepared = Self.preparationForCommittedRepair(
                            pending.preparation,
                            report: refreshedReport
                        )
                        let authorizedPreparation = try await bridgeCoordinator.validateMutationAuthority(
                            preparation: prepared,
                            report: refreshedReport
                        )
                        if let committedReport = pending.committedReport {
                            try mutationGate.requireChainedLocalCommitCompletion(
                                preparation: authorizedPreparation,
                                committedReport: committedReport,
                                report: refreshedReport,
                                resolutions: recoveryResolutions
                            )
                        } else {
                            try mutationGate.requireLocalCommitCompletion(
                                preparation: authorizedPreparation,
                                report: refreshedReport,
                                resolutions: recoveryResolutions
                            )
                        }
                    }
                )
                try mutationGate.markLocalCommitSucceeded()
            } catch {
                let currentReport = mutationGate.pendingState?.report ?? pending.report
                switch try await worker.commitState(for: currentReport) {
                case .committed:
                    try mutationGate.markLocalCommitSucceeded()
                case .notCommitted:
                    mutationGate.clearPendingLocalCommitAfterRollback()
                    throw error
                case .indeterminate:
                    throw CoordinatedPublicIDRepairError.localCommitStateIndeterminate
                }
            }

        case .indeterminate:
            let recoveryAssessment = try await worker.assessIndeterminateRecovery(
                for: pending.report
            )
            if recoveryAssessment.requiresManualResolution {
                let issues = recoveryAssessment.manualResolutionIssues
                let selectionByIssueID = Dictionary(
                    uniqueKeysWithValues: resolutions.map {
                        ($0.unresolvedReferenceID, $0.selectedCandidateStableRecordIdentifier)
                    }
                )
                let selectionsAreComplete = !issues.isEmpty && issues.allSatisfy { issue in
                    guard !issue.candidates.isEmpty,
                          let selected = selectionByIssueID[issue.id] else {
                        return false
                    }
                    return issue.candidates.contains {
                        $0.stableRecordIdentifier == selected
                    }
                }
                guard selectionsAreComplete else {
                    throw PublicIDRepairBridgeResolutionRequired(issues: issues)
                }
                let issueIDs = Set(issues.map(\.id))
                let manualResolutions = resolutions.filter {
                    issueIDs.contains($0.unresolvedReferenceID)
                }
                _ = try await worker.resolveIndeterminateRecovery(
                    report: pending.report,
                    resolutions: manualResolutions,
                    willCommit: { [mutationGate, bridgeCoordinator] refreshedReport in
                        let prepared = Self.preparationForCommittedRepair(
                            pending.preparation,
                            report: refreshedReport
                        )
                        let authorizedPreparation = try await bridgeCoordinator.validateMutationAuthority(
                            preparation: prepared,
                            report: refreshedReport
                        )
                        if let committedReport = pending.committedReport {
                            try mutationGate.requireChainedLocalCommitCompletion(
                                preparation: authorizedPreparation,
                                committedReport: committedReport,
                                report: refreshedReport,
                                resolutions: resolutions
                            )
                        } else {
                            try mutationGate.requireLocalCommitCompletion(
                                preparation: authorizedPreparation,
                                report: refreshedReport,
                                resolutions: resolutions
                            )
                        }
                    }
                )
                try mutationGate.markLocalCommitSucceeded()
                return
            }

            guard let action = Self.selectedRecoveryChoice(
                from: resolutions,
                report: pending.report
            ) else {
                throw PublicIDRepairBridgeResolutionRequired(
                    issues: [
                        Self.indeterminateRecoveryIssue(
                            report: pending.report,
                            assessment: recoveryAssessment
                        )
                    ]
                )
            }
            let expectedAction: PublicIDRepairRecoveryChoice
            if recoveryAssessment.canContinueManifestRepair {
                expectedAction = .continueManifestRepair
            } else if recoveryAssessment.requiresBackupRestore {
                expectedAction = .restorePreRepairBackup
            } else {
                throw PublicIDRepairRecoveryError.invalidChoice
            }
            guard action == expectedAction else {
                throw PublicIDRepairRecoveryError.invalidChoice
            }

            let recoveryResolutions = workerResolutions(
                resolutions,
                report: pending.report
            )
            _ = try await worker.recoverIndeterminateRepair(
                report: pending.report,
                action: action,
                willCommit: { [mutationGate, bridgeCoordinator] refreshedReport in
                    let prepared = Self.preparationForCommittedRepair(
                        pending.preparation,
                        report: refreshedReport
                    )
                    let authorizedPreparation = try await bridgeCoordinator.validateMutationAuthority(
                        preparation: prepared,
                        report: refreshedReport
                    )
                    if let committedReport = pending.committedReport {
                        try mutationGate.requireChainedLocalCommitCompletion(
                            preparation: authorizedPreparation,
                            committedReport: committedReport,
                            report: refreshedReport,
                            resolutions: recoveryResolutions
                        )
                    } else {
                        try mutationGate.requireLocalCommitCompletion(
                            preparation: authorizedPreparation,
                            report: refreshedReport,
                            resolutions: recoveryResolutions
                        )
                    }
                }
            )
            try mutationGate.markLocalCommitSucceeded()
        }
    }

    private func convergeAfterRepair(
        preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport
    ) async throws -> PublicIDRepairBridgeConvergenceOutcome {
        do {
            try await bridgeCoordinator.convergeAfterRepair(
                preparation: preparation,
                report: report
            )
            return .converged(report)
        } catch let error as PublicIDRepairBridgeResolutionRequired {
            try mutationGate.recordBridgeResolutionIssues(error.issues)
            let automaticResolutions = error.issues.compactMap { issue
                -> PublicIDRepairReferenceResolution? in
                guard issue.kind == .bridgeRecordOwner,
                      issue.candidates.count == 1,
                      let candidate = issue.candidates.first else {
                    return nil
                }
                return PublicIDRepairReferenceResolution(
                    unresolvedReferenceID: issue.id,
                    selectedCandidateStableRecordIdentifier: candidate.stableRecordIdentifier
                )
            }
            guard !automaticResolutions.isEmpty,
                  automaticResolutions.count == error.issues.count else {
                throw error
            }

            try mutationGate.applyBridgeResolutionSelections(automaticResolutions)
            return .automaticResolutionApplied(error.issues)
        }
    }

    private func workerResolutions(
        _ base: [PublicIDRepairReferenceResolution],
        report: PublicIDRepairReport
    ) -> [PublicIDRepairReferenceResolution] {
        let bridgeDirectives = (report.bridgeCollisionResolutions ?? [])
            .flatMap(\.workerResolutionDirectives)
        let workerBase = base.filter { resolution in
            PublicIDRepairRecoveryChoice(
                rawValue: resolution.selectedCandidateStableRecordIdentifier
            ) == nil
                && !resolution.selectedCandidateStableRecordIdentifier.hasPrefix(
                    "local-recovery-candidate-v1|"
                )
        }
        return mergedResolutions(workerBase, bridgeDirectives)
    }

    private func mergedResolutions(
        _ persisted: [PublicIDRepairReferenceResolution],
        _ requested: [PublicIDRepairReferenceResolution]
    ) -> [PublicIDRepairReferenceResolution] {
        var byID: [String: PublicIDRepairReferenceResolution] = [:]
        for resolution in persisted {
            byID[resolution.id] = resolution
        }
        for resolution in requested {
            byID[resolution.id] = resolution
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    private static func selectedRecoveryChoice(
        from resolutions: [PublicIDRepairReferenceResolution],
        report: PublicIDRepairReport
    ) -> PublicIDRepairRecoveryChoice? {
        let actions = resolutions.compactMap {
            PublicIDRepairRecoveryChoice(rawValue: $0.selectedCandidateStableRecordIdentifier)
        }
        guard Set(actions).count == 1 else { return nil }
        // The pending report supplied by the gate is the binding to the expected journal and
        // manifest generation. No candidate can redirect recovery to another transaction.
        _ = report.manifest.currentGenerationNumber
        return actions.first
    }

    private static func indeterminateRecoveryIssue(
        report: PublicIDRepairReport,
        assessment: PublicIDRepairIndeterminateRecoveryAssessment
    ) -> PublicIDRepairUnresolvedReference {
        let mapping = report.manifest.recordMappings.first
        let entityType = mapping?.entityType ?? .herd
        let originalID = mapping?.originalPublicID
            ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let finalID = mapping?.finalPublicID ?? originalID
        let action: PublicIDRepairRecoveryChoice = assessment.canContinueManifestRepair
            ? .continueManifestRepair
            : .restorePreRepairBackup
        let description: String
        let detail: String
        let reason: String
        let resultingID: UUID
        switch action {
        case .continueManifestRepair:
            description = "Continue repair safely"
            detail = "Replay only the missing transformations already authorized by the durable manifest. A new backup and repair generation are created first."
            reason = "The local commit is only partially observable, but every manifest transformation can still be identified uniquely. Already-correct identities will not be changed or regenerated."
            resultingID = finalID
        case .restorePreRepairBackup:
            description = "Restore pre-repair backup"
            detail = "Use the exact backup bound to this pending manifest generation. yaHerd first backs up the current damaged state, verifies the restoration boundary, then resumes the same manifest repair path."
            reason = assessment.blockingReason.map {
                "Forward repair cannot be proven safe: \($0) Choose the verified backup fallback to continue without merging unrelated identities."
            } ?? "Forward repair cannot be proven safe. Choose the verified backup fallback to continue without merging unrelated identities."
            resultingID = originalID
        }
        return PublicIDRepairUnresolvedReference(
            kind: .indeterminateLocalRepairRecovery,
            entityType: entityType,
            recordDescription: "Pending local public-ID repair",
            stableRecordIdentifier: PublicIDRepairRecoverySelection.issueStableIdentifier,
            fieldName: "recoveryAction",
            referencedPublicID: originalID,
            reason: reason,
            candidates: [
                PublicIDRepairResolutionCandidate(
                    stableRecordIdentifier: action.rawValue,
                    recordDescription: description,
                    detail: detail,
                    resultingPublicID: resultingID
                )
            ]
        )
    }

    private static func preparationForCommittedRepair(
        _ preparation: PublicIDRepairBridgePreparation,
        report: PublicIDRepairReport
    ) -> PublicIDRepairBridgePreparation {
        guard preparation.identity == .iCloud else { return preparation }
        let replacementHerdTargets: [PublicIDRepairBridgeTargetIdentity] = report.replacements.compactMap { replacement -> PublicIDRepairBridgeTargetIdentity? in
            guard replacement.entityType == .herd else { return nil }
            return PublicIDRepairBridgeTargetIdentity(
                herdPublicID: replacement.replacementPublicID,
                location: .bridgeRecordMissing
            )
        }
        guard !replacementHerdTargets.isEmpty else { return preparation }
        return PublicIDRepairBridgePreparation(
            identity: preparation.identity,
            targets: preparation.targets + replacementHerdTargets
        )
    }
}
