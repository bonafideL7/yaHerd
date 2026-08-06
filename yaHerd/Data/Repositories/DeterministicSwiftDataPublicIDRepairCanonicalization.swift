import Foundation
import SwiftData

extension DeterministicSwiftDataPublicIDRepairService {
    func appendNodes<Model>(
        _ records: [Model],
        entityType: PublicIDRepairEntityType,
        collaborationType: CollaborationAggregateType,
        publicID: @escaping (Model) -> UUID,
        assign: @escaping (Model, UUID) -> Void,
        description: @escaping (Model) -> String,
        to nodes: inout [AggregateNode]
    ) where Model: PersistentModel, Model: CollaborativelyMutableAggregate {
        for record in records {
            nodes.append(
                AggregateNode(
                    entityType: entityType,
                    collaborationType: collaborationType,
                    aggregate: record,
                    localIdentifier: localRecordIdentifier(record),
                    recordDescription: description(record),
                    readPublicID: { publicID(record) },
                    assignPublicID: { assign(record, $0) },
                    snapshotKey: stableSnapshotKey(
                        CollaborationFieldSnapshotProvider.snapshot(for: record)
                    )
                )
            )
        }
    }

    func makeEntityPlan(
        nodes: [AggregateNode],
        entityType: PublicIDRepairEntityType,
        graphFingerprintByLocalIdentifier: [String: String],
        revisionMetadata: [CollaborationAggregateKey: CollaborationRevisionMetadata]
    ) -> EntityPlan {
        let grouped = Dictionary(grouping: nodes, by: { $0.readPublicID() })
        let duplicateGroups = grouped
            .filter { $0.value.count > 1 }
            .sorted { $0.key.uuidString < $1.key.uuidString }
        var replacements: [PlannedReplacement] = []
        var candidates: [DuplicateCandidate] = []
        var usedIDs = Set(nodes.map { $0.readPublicID() })

        for (retainedID, duplicateNodes) in duplicateGroups {
            let metadata = duplicateNodes.first.map {
                revisionMetadata[
                    CollaborationAggregateKey(type: $0.collaborationType, publicID: retainedID)
                ]
            } ?? nil
            let ordered = duplicateNodes.sorted { lhs, rhs in
                canonicalSortKey(
                    node: lhs,
                    metadata: metadata,
                    graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier
                ) < canonicalSortKey(
                    node: rhs,
                    metadata: metadata,
                    graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier
                )
            }

            for (ordinal, node) in ordered.enumerated() {
                let graphFingerprint = graphFingerprintByLocalIdentifier[node.localIdentifier] ?? ""
                let stableIdentifier = duplicateCandidateIdentifier(
                    entityType: entityType,
                    retainedID: retainedID,
                    snapshotKey: node.snapshotKey,
                    graphFingerprint: graphFingerprint,
                    ordinal: ordinal
                )
                let resultingID: UUID
                if ordinal == 0 {
                    resultingID = retainedID
                } else {
                    resultingID = makeReplacementID(
                        entityType: entityType,
                        retainedID: retainedID,
                        stableRecordIdentifier: stableIdentifier,
                        usedIDs: &usedIDs
                    )
                    replacements.append(
                        PlannedReplacement(
                            report: PublicIDRepairReplacement(
                                entityType: entityType,
                                recordDescription: node.recordDescription,
                                stableRecordIdentifier: stableIdentifier,
                                retainedPublicID: retainedID,
                                replacementPublicID: resultingID
                            ),
                            localRecordIdentifier: node.localIdentifier,
                            readPublicID: node.readPublicID,
                            assignPublicID: node.assignPublicID
                        )
                    )
                }
                candidates.append(
                    DuplicateCandidate(
                        entityType: entityType,
                        localIdentifier: node.localIdentifier,
                        stableRecordIdentifier: stableIdentifier,
                        recordDescription: node.recordDescription,
                        detail: candidateDetail(
                            snapshotKey: node.snapshotKey,
                            graphFingerprint: graphFingerprint,
                            retainsOriginalID: ordinal == 0
                        ),
                        retainedPublicID: retainedID,
                        resultingPublicID: resultingID
                    )
                )
            }
        }

        return EntityPlan(
            assessment: PublicIDRepairEntityAssessment(
                entityType: entityType,
                scannedRecordCount: nodes.count,
                duplicateGroupCount: duplicateGroups.count,
                duplicateRecordCount: replacements.count
            ),
            replacements: replacements,
            candidates: candidates
        )
    }

    func canonicalSortKey(
        node: AggregateNode,
        metadata: CollaborationRevisionMetadata?,
        graphFingerprintByLocalIdentifier: [String: String]
    ) -> String {
        let fields = CollaborationFieldSnapshotProvider.snapshot(for: node.aggregate)
        let revisionRank = metadata?.currentFieldValues == fields ? "0" : "1"
        return [
            revisionRank,
            deterministicDigest(node.snapshotKey),
            graphFingerprintByLocalIdentifier[node.localIdentifier] ?? "",
        ].joined(separator: "|")
    }

    func duplicateCandidateIdentifier(
        entityType: PublicIDRepairEntityType,
        retainedID: UUID,
        snapshotKey: String,
        graphFingerprint: String,
        ordinal: Int
    ) -> String {
        [
            entityType.rawValue,
            retainedID.uuidString.lowercased(),
            deterministicDigest(snapshotKey),
            graphFingerprint,
            "candidate-\(ordinal)",
        ].joined(separator: "|")
    }

    func candidateDetail(
        snapshotKey: String,
        graphFingerprint: String,
        retainsOriginalID: Bool
    ) -> String {
        let role = retainsOriginalID ? "Keeps the existing public ID" : "Receives a replacement public ID"
        return "\(role). Record fingerprint \(deterministicDigest(snapshotKey).prefix(10)); relationship fingerprint \(graphFingerprint.prefix(10))."
    }

    func makeReplacementID(
        entityType: PublicIDRepairEntityType,
        retainedID: UUID,
        stableRecordIdentifier: String,
        usedIDs: inout Set<UUID>
    ) -> UUID {
        var attempt = 0
        while true {
            let seed = [
                "yaHerd-public-id-repair-v4",
                entityType.rawValue,
                retainedID.uuidString.lowercased(),
                stableRecordIdentifier,
                String(attempt),
            ].joined(separator: "|")
            let candidate = deterministicUUID(seed: seed)
            if usedIDs.insert(candidate).inserted {
                return candidate
            }
            attempt += 1
        }
    }

    func preferredRevisionMetadata(
        _ records: [CollaborationRevisionRecord]
    ) -> [CollaborationAggregateKey: CollaborationRevisionMetadata] {
        var result: [CollaborationAggregateKey: CollaborationRevisionMetadata] = [:]
        for record in records {
            let key = record.key
            guard let existing = result[key] else {
                result[key] = record.metadata
                continue
            }
            if record.revision > existing.revision
                || (record.revision == existing.revision && record.modifiedAt > existing.modifiedAt)
                || (
                    record.revision == existing.revision
                        && record.modifiedAt == existing.modifiedAt
                        && stableSnapshotKey(record.metadata.currentFieldValues)
                            < stableSnapshotKey(existing.currentFieldValues)
                ) {
                result[key] = record.metadata
            }
        }
        return result
    }

}
