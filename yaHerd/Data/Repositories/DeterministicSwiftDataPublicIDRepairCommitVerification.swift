import Foundation

extension DeterministicSwiftDataPublicIDRepairService {
    func commitState(for report: PublicIDRepairReport) throws -> PublicIDRepairCommitState {
        guard !report.replacements.isEmpty else { return .indeterminate }

        let loaded = try loadRecords()
        let currentIDCounts = currentRepairIDCounts(loaded: loaded)
        let replacementPresence = report.replacements.map { replacement in
            currentIDCounts[replacement.entityType, default: [:]][replacement.replacementPublicID, default: 0]
        }

        if replacementPresence.allSatisfy({ $0 == 1 }) {
            // The repair save is atomic. Observing every deterministic replacement ID proves
            // the journaled transaction committed even if a new, unrelated duplicate arrived
            // after the save and before the process relaunched.
            return .committed
        }

        guard replacementPresence.allSatisfy({ $0 == 0 }) else {
            // A partial set of deterministic replacement IDs cannot be produced by the repair's
            // single SwiftData save. Treat it as ambiguous external change and fail closed.
            return .indeterminate
        }

        guard preRepairBackupIsStillPresent(report: report, loaded: loaded) else {
            // With no replacement IDs, the transaction may not have committed, but recovery may
            // not retry unless the exact pre-repair records are still present. This protects
            // against a committed repair whose records were subsequently changed or removed.
            return .indeterminate
        }

        return .notCommitted
    }

    private func currentRepairIDCounts(
        loaded: LoadedRecords
    ) -> [PublicIDRepairEntityType: [UUID: Int]] {
        var result: [PublicIDRepairEntityType: [UUID: Int]] = [:]

        func record(_ entityType: PublicIDRepairEntityType, _ publicID: UUID) {
            result[entityType, default: [:]][publicID, default: 0] += 1
        }

        for aggregate in loaded.allAggregates {
            record(publicIDRepairEntityType(for: aggregate), aggregate.collaborationKey.publicID)
        }
        for template in loaded.workingProtocolTemplates {
            for item in template.items {
                record(.workingProtocolTemplate, item.id)
            }
        }
        for session in loaded.workingSessions {
            for item in session.protocolItems {
                record(.workingSession, item.id)
            }
        }

        return result
    }

    private func preRepairBackupIsStillPresent(
        report: PublicIDRepairReport,
        loaded: LoadedRecords
    ) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: report.backupPath)) else {
            return false
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(PublicIDRepairBackup.self, from: data) else {
            return false
        }

        var currentCounts: [String: Int] = [:]
        for aggregate in loaded.allAggregates {
            currentCounts[commitVerificationKey(
                entityType: publicIDRepairEntityType(for: aggregate),
                publicID: aggregate.collaborationKey.publicID,
                herdPublicID: aggregate.collaborationHerdPublicID,
                sharedFields: CollaborationFieldSnapshotProvider.snapshot(for: aggregate)
            ), default: 0] += 1
        }

        var requiredCounts: [String: Int] = [:]
        for aggregate in backup.aggregates {
            requiredCounts[commitVerificationKey(
                entityType: aggregate.entityType,
                publicID: aggregate.publicID,
                herdPublicID: aggregate.herdPublicID,
                sharedFields: aggregate.sharedFields
            ), default: 0] += 1
        }

        return requiredCounts.allSatisfy { key, requiredCount in
            currentCounts[key, default: 0] >= requiredCount
        }
    }

    private func commitVerificationKey(
        entityType: PublicIDRepairEntityType,
        publicID: UUID,
        herdPublicID: UUID?,
        sharedFields: CollaborationFieldSnapshot
    ) -> String {
        [
            entityType.rawValue,
            publicID.uuidString.lowercased(),
            herdPublicID?.uuidString.lowercased() ?? "none",
            deterministicDigest(stableSnapshotKey(sharedFields)),
        ].joined(separator: "|")
    }
}
