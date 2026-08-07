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
        revisionMetadata: [CollaborationAggregateKey: CollaborationRevisionMetadata],
        resolutions: [String: String] = [:]
    ) -> EntityPlan {
        let grouped = Dictionary(grouping: nodes, by: { $0.readPublicID() })
        let duplicateGroups = grouped
            .filter { $0.value.count > 1 }
            .sorted { $0.key.uuidString < $1.key.uuidString }
        let duplicateRecordCount = duplicateGroups.reduce(0) { partial, group in
            partial + group.value.count - 1
        }
        var replacements: [PlannedReplacement] = []
        var candidates: [DuplicateCandidate] = []
        var unresolvedIssues: [PublicIDRepairUnresolvedReference] = []
        var usedIDs = Set(nodes.map { $0.readPublicID() })

        for (retainedID, duplicateNodes) in duplicateGroups {
            let metadata = duplicateNodes.first.map {
                revisionMetadata[
                    CollaborationAggregateKey(type: $0.collaborationType, publicID: retainedID)
                ]
            } ?? nil
            let keyedNodes = duplicateNodes.map { node in
                (
                    node,
                    canonicalSortKey(
                        node: node,
                        metadata: metadata,
                        graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier
                    )
                )
            }
            let tiedKeys = Dictionary(grouping: keyedNodes, by: { $0.1 })
                .filter { $0.value.count > 1 }
            guard tiedKeys.isEmpty else {
                unresolvedIssues.append(
                    PublicIDRepairUnresolvedReference(
                        kind: .canonicalRecord,
                        entityType: entityType,
                        recordDescription: "Indistinguishable duplicate \(entityType.displayName.lowercased())",
                        stableRecordIdentifier: [
                            entityType.rawValue,
                            retainedID.uuidString.lowercased(),
                            "canonical-order-unresolved",
                        ].joined(separator: "|"),
                        fieldName: "publicID",
                        referencedPublicID: retainedID,
                        reason: "These duplicate records still have identical portable field and relationship fingerprints. Change one record or one of its relationships so the records can be distinguished before repair; no store-local identity is used to guess a canonical record."
                    )
                )
                continue
            }

            let portableOrder = keyedNodes.sorted { $0.1 < $1.1 }.map { $0.0 }
            let entries = portableOrder.enumerated().map { ordinal, node in
                let graphFingerprint = graphFingerprintByLocalIdentifier[node.localIdentifier] ?? ""
                let stableIdentifier = duplicateCandidateIdentifier(
                    entityType: entityType,
                    retainedID: retainedID,
                    snapshotKey: node.snapshotKey,
                    graphFingerprint: graphFingerprint,
                    ordinal: ordinal
                )
                return (
                    node: node,
                    graphFingerprint: graphFingerprint,
                    stableIdentifier: stableIdentifier
                )
            }

            var selectedCanonicalLocalIdentifier: String?
            if entityType == .herd {
                let issue = duplicateHerdCanonicalIssue(
                    retainedID: retainedID,
                    entries: entries
                )
                if let selectedStableIdentifier = resolutions[issue.id],
                   let selected = entries.first(where: {
                       $0.stableIdentifier == selectedStableIdentifier
                   }) {
                    selectedCanonicalLocalIdentifier = selected.node.localIdentifier
                } else {
                    unresolvedIssues.append(issue)
                }
            }

            let defaultCanonicalLocalIdentifier = entries.first?.node.localIdentifier
            let canonicalLocalIdentifier = selectedCanonicalLocalIdentifier
                ?? defaultCanonicalLocalIdentifier

            for entry in entries {
                let retainsOriginalID = entry.node.localIdentifier == canonicalLocalIdentifier
                let resultingID: UUID
                if retainsOriginalID {
                    resultingID = retainedID
                } else {
                    resultingID = makeReplacementID(
                        entityType: entityType,
                        retainedID: retainedID,
                        stableRecordIdentifier: entry.stableIdentifier,
                        usedIDs: &usedIDs
                    )
                    replacements.append(
                        PlannedReplacement(
                            report: PublicIDRepairReplacement(
                                entityType: entityType,
                                recordDescription: entry.node.recordDescription,
                                stableRecordIdentifier: entry.stableIdentifier,
                                retainedPublicID: retainedID,
                                replacementPublicID: resultingID
                            ),
                            localRecordIdentifier: entry.node.localIdentifier,
                            readPublicID: entry.node.readPublicID,
                            assignPublicID: entry.node.assignPublicID
                        )
                    )
                }
                candidates.append(
                    DuplicateCandidate(
                        entityType: entityType,
                        localIdentifier: entry.node.localIdentifier,
                        stableRecordIdentifier: entry.stableIdentifier,
                        recordDescription: entry.node.recordDescription,
                        detail: candidateDetail(
                            snapshotKey: entry.node.snapshotKey,
                            graphFingerprint: entry.graphFingerprint,
                            retainsOriginalID: retainsOriginalID
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
                duplicateRecordCount: duplicateRecordCount
            ),
            replacements: replacements,
            candidates: candidates,
            unresolvedIssues: unresolvedIssues
        )
    }

    private func duplicateHerdCanonicalIssue(
        retainedID: UUID,
        entries: [(node: AggregateNode, graphFingerprint: String, stableIdentifier: String)]
    ) -> PublicIDRepairUnresolvedReference {
        PublicIDRepairUnresolvedReference(
            kind: .canonicalRecord,
            entityType: .herd,
            recordDescription: "Duplicate Herd sharing identity",
            stableRecordIdentifier: [
                PublicIDRepairEntityType.herd.rawValue,
                retainedID.uuidString.lowercased(),
                "shared-bridge-owner-choice",
            ].joined(separator: "|"),
            fieldName: "sharedBridgeOwner",
            referencedPublicID: retainedID,
            reason: "Choose which Herd is the one already represented by the existing iCloud sharing bridge. That Herd keeps the current public ID and share. Every other duplicate Herd receives a deterministic replacement ID and becomes a separate locally owned herd before shared-data convergence resumes.",
            candidates: entries.map { entry in
                PublicIDRepairResolutionCandidate(
                    stableRecordIdentifier: entry.stableIdentifier,
                    recordDescription: entry.node.recordDescription,
                    detail: "Keep this Herd attached to the existing shared bridge. Record fingerprint \(deterministicDigest(entry.node.snapshotKey).prefix(10)); relationship fingerprint \(entry.graphFingerprint.prefix(10)).",
                    resultingPublicID: retainedID
                )
            }
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
