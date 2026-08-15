import Foundation

enum PublicIDRepairRecoveryChoice: String, Codable, Equatable, Sendable {
    case continueManifestRepair
    case restorePreRepairBackup
}

enum PublicIDRepairRecoveryTransformationState: String, Codable, Equatable, Sendable {
    case alreadyApplied
    case definitelyNotApplied
    case contradictoryOrAmbiguous
}

enum PublicIDRepairIndeterminateRecoveryCapability: String, Equatable, Sendable {
    case manifestForwardRecoveryAvailable
    case verifiedBackupRestoreAvailable
    case manualRecoveryResolutionRequired
}

enum PublicIDRepairRecoveryEvidenceKind: String, Equatable, Sendable {
    case matchedSafelyToBackup
    case repairOwnedValueChangedOnIdentifiableRecord
    case recordNoLongerUniquelyMatchesBackup
    case recordAppearsMissing
    case multiplePlausibleCurrentRecords
    case manifestEvidenceContradiction
}

struct PublicIDRepairRecoveryEvidence: Equatable, Sendable {
    let stableRecordIdentifier: String
    let kind: PublicIDRepairRecoveryEvidenceKind
    let description: String
}

struct PublicIDRepairIndeterminateRecoveryAssessment: Equatable, Sendable {
    let transformationStates: [PublicIDRepairRecoveryTransformationState]
    let capability: PublicIDRepairIndeterminateRecoveryCapability
    let blockingReason: String?
    let evidence: [PublicIDRepairRecoveryEvidence]
    let manualResolutionIssues: [PublicIDRepairUnresolvedReference]

    init(
        transformationStates: [PublicIDRepairRecoveryTransformationState],
        capability: PublicIDRepairIndeterminateRecoveryCapability,
        blockingReason: String?,
        evidence: [PublicIDRepairRecoveryEvidence] = [],
        manualResolutionIssues: [PublicIDRepairUnresolvedReference] = []
    ) {
        self.transformationStates = transformationStates
        self.capability = capability
        self.blockingReason = blockingReason
        self.evidence = evidence

        if capability == .manualRecoveryResolutionRequired,
           manualResolutionIssues.isEmpty {
            // A non-restorable contradiction must still produce a visible fail-closed diagnostic.
            // The worker normally supplies a semantic record-binding issue; this fallback covers
            // evidence such as an unlocatable treatment item where no safe current candidate can
            // be offered. It deliberately supplies no candidate rather than guessing identity or
            // advertising the backup restore path that the planner already proved unusable.
            let blocker = evidence.first(where: {
                $0.kind == .recordAppearsMissing
                    || $0.kind == .multiplePlausibleCurrentRecords
                    || $0.kind == .manifestEvidenceContradiction
                    || $0.kind == .recordNoLongerUniquelyMatchesBackup
            })
            let stableID = blocker?.stableRecordIdentifier
                ?? PublicIDRepairRecoverySelection.issueStableIdentifier
            let reason = blocker?.description
                ?? blockingReason
                ?? "The current local graph cannot be matched safely to the pending manifest or its bound backup."
            self.manualResolutionIssues = [
                PublicIDRepairUnresolvedReference(
                    kind: .indeterminateLocalRepairRecovery,
                    entityType: .herd,
                    recordDescription: "Pending manifest identity cannot be resolved safely",
                    stableRecordIdentifier: PublicIDRepairRecoverySelection.manualIssueStableIdentifier(
                        for: stableID
                    ),
                    fieldName: "manualRecoveryEvidence",
                    referencedPublicID: UUID(
                        uuidString: "00000000-0000-0000-0000-000000000000"
                    )!,
                    reason: "\(reason) No verified backup restore or safe semantic binding is currently available. Recovery remains gated rather than inferring deletion or choosing a record automatically.",
                    candidates: []
                )
            ]
        } else {
            self.manualResolutionIssues = manualResolutionIssues
        }
    }

    var alreadyAppliedCount: Int {
        transformationStates.filter { $0 == .alreadyApplied }.count
    }

    var missingCount: Int {
        transformationStates.filter { $0 == .definitelyNotApplied }.count
    }

    var contradictoryOrAmbiguousCount: Int {
        transformationStates.filter { $0 == .contradictoryOrAmbiguous }.count
    }

    var canContinueManifestRepair: Bool {
        capability == .manifestForwardRecoveryAvailable
    }

    var requiresBackupRestore: Bool {
        capability == .verifiedBackupRestoreAvailable
    }

    var requiresManualResolution: Bool {
        capability == .manualRecoveryResolutionRequired
    }
}

enum PublicIDRepairRecoveryError: LocalizedError, Equatable {
    case unsupported
    case invalidChoice
    case manifestContradiction(String)
    case backupUnavailable
    case backupFormatUnsupported(Int)
    case backupTransactionMismatch
    case ambiguousRecord(String)
    case unrelatedGraphDrift(String)
    case restorationVerificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            "This persistence worker does not support indeterminate public-ID repair recovery. Normal edits and synchronization remain blocked."
        case .invalidChoice:
            "The selected public-ID repair recovery action is not valid for the current manifest state. Scan again in Sync Diagnostics before continuing."
        case .manifestContradiction(let details):
            "The durable public-ID repair manifest is contradictory and cannot be replayed safely. \(details)"
        case .backupUnavailable:
            "The exact backup bound to the pending public-ID repair generation is unavailable. Recovery remains blocked rather than using another backup."
        case .backupFormatUnsupported(let version):
            "The pending public-ID repair backup uses unsupported format version \(version). Recovery remains blocked."
        case .backupTransactionMismatch:
            "The selected public-ID repair backup does not match the pending manifest generation. Recovery remains blocked rather than merging unrelated identities."
        case .ambiguousRecord(let details):
            "The current local graph cannot be matched uniquely to the pending public-ID repair manifest. \(details)"
        case .unrelatedGraphDrift(let details):
            "Local data changed outside the fields owned by public-ID repair. Backup restoration remains blocked so unrelated edits are not silently overwritten. \(details)"
        case .restorationVerificationFailed(let details):
            "The pre-repair backup was applied but the restored repair boundary could not be verified. The mutation gate remains closed. \(details)"
        }
    }
}

protocol PublicIDRepairTransactionalRecovering: Sendable {
    func assessIndeterminateRecovery(
        for report: PublicIDRepairReport
    ) async throws -> PublicIDRepairIndeterminateRecoveryAssessment

    func recoverIndeterminateRepair(
        report: PublicIDRepairReport,
        action: PublicIDRepairRecoveryChoice,
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport

    func resolveIndeterminateRecovery(
        report: PublicIDRepairReport,
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport
}

extension PublicIDRepairTransactionalRecovering {
    func resolveIndeterminateRecovery(
        report: PublicIDRepairReport,
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport {
        throw PublicIDRepairRecoveryError.unsupported
    }
}

extension PublicIDRepairTransactionalService {
    func assessIndeterminateRecovery(
        for report: PublicIDRepairReport
    ) async throws -> PublicIDRepairIndeterminateRecoveryAssessment {
        guard let recovering = self as? any PublicIDRepairTransactionalRecovering else {
            throw PublicIDRepairRecoveryError.unsupported
        }
        return try await recovering.assessIndeterminateRecovery(for: report)
    }

    func recoverIndeterminateRepair(
        report: PublicIDRepairReport,
        action: PublicIDRepairRecoveryChoice,
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport {
        guard let recovering = self as? any PublicIDRepairTransactionalRecovering else {
            throw PublicIDRepairRecoveryError.unsupported
        }
        return try await recovering.recoverIndeterminateRepair(
            report: report,
            action: action,
            willCommit: willCommit
        )
    }

    func resolveIndeterminateRecovery(
        report: PublicIDRepairReport,
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport {
        guard let recovering = self as? any PublicIDRepairTransactionalRecovering else {
            throw PublicIDRepairRecoveryError.unsupported
        }
        return try await recovering.resolveIndeterminateRecovery(
            report: report,
            resolutions: resolutions,
            willCommit: willCommit
        )
    }
}

enum PublicIDRepairRecoverySelection {
    static let issueStableIdentifier = "public-id-repair|indeterminate-local-commit"
    static let manualIssuePrefix = "public-id-repair|indeterminate-local-identity"
    private static let bindingMarkerPrefix = "local-recovery-binding-v1"

    static func candidateIdentifier(
        for action: PublicIDRepairRecoveryChoice,
        generation: Int
    ) -> String {
        "\(issueStableIdentifier)|generation-\(generation)|\(action.rawValue)"
    }

    static func action(
        from candidateIdentifier: String,
        expectedGeneration: Int
    ) -> PublicIDRepairRecoveryChoice? {
        PublicIDRepairRecoveryChoice.allCases.first { action in
            candidateIdentifier == self.candidateIdentifier(
                for: action,
                generation: expectedGeneration
            )
        }
    }

    static func manualIssueStableIdentifier(for manifestStableIdentifier: String) -> String {
        "\(manualIssuePrefix)|\(encoded(manifestStableIdentifier))"
    }

    static func manualBindingMarker(
        issueID: String,
        candidateStableRecordIdentifier: String
    ) -> String {
        [
            bindingMarkerPrefix,
            encoded(issueID),
            encoded(candidateStableRecordIdentifier),
        ].joined(separator: "|")
    }

    static func manualBindings(in manifest: PublicIDRepairManifest) -> [String: String] {
        var latestByIssueID: [String: String] = [:]
        for generation in manifest.generations.sorted(by: { $0.number < $1.number }) {
            for marker in generation.selectedResolutionIDs {
                let parts = marker.split(separator: "|", omittingEmptySubsequences: false)
                guard parts.count == 3,
                      parts[0] == Substring(bindingMarkerPrefix),
                      let issueID = decoded(String(parts[1])),
                      let candidateID = decoded(String(parts[2])) else {
                    continue
                }
                // Recovery bindings are evidence, not public-ID authority. If a user corrects a
                // prior binding before local replay, the latest explicit decision is the one the
                // planner should evaluate while the immutable manifest mappings remain unchanged.
                latestByIssueID[issueID] = candidateID
            }
        }

        let candidateCounts = Dictionary(
            grouping: latestByIssueID.values,
            by: { $0 }
        ).mapValues(\.count)
        var oneToOneBindings: [String: String] = [:]
        for (issueID, candidateID) in latestByIssueID
        where candidateCounts[candidateID] == 1 {
            oneToOneBindings[issueID] = candidateID
        }
        // Never let two manifest identities resolve to the same current record. Conflicting
        // bindings remain durably auditable in their generations, but are ignored as recovery
        // evidence so the planner returns to explicit manual resolution instead of attempting a
        // many-to-one identity merge.
        return oneToOneBindings
    }

    private static func encoded(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    private static func decoded(_ value: String) -> String? {
        guard let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension PublicIDRepairRecoveryChoice: CaseIterable {}

extension PublicIDRepairService {
    func recoverIndeterminateRepair(
        action: PublicIDRepairRecoveryChoice
    ) async throws -> PublicIDRepairReport {
        // The coordinated service validates this action against the exact pending manifest
        // generation before any mutation. The façade never exposes backup JSON or import details.
        try await repair(
            resolutions: [
                PublicIDRepairReferenceResolution(
                    unresolvedReferenceID: PublicIDRepairRecoverySelection.issueStableIdentifier,
                    selectedCandidateStableRecordIdentifier: action.rawValue
                )
            ]
        )
    }
}
