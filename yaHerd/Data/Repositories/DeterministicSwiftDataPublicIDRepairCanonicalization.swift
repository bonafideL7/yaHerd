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
                    herdPublicID: record.collaborationHerdPublicID,
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
        relationshipContextByLocalIdentifier: [String: String],
        revisionMetadata: [CollaborationAggregateKey: CollaborationRevisionMetadata],
        resolutions: [String: String] = [:]
    ) -> EntityPlan {
        let grouped = Dictionary(grouping: nodes, by: { $0.readPublicID() })
        let duplicateGroups = grouped
            .filter { $0.value.count > 1 }
            .sorted { $0.key.uuidString < $1.key.uuidString }
        let repairGroups = grouped
            .filter { retainedID, groupedNodes in
                groupedNodes.count > 1
                    || groupedNodes.contains { node in
                        forcedCrossHerdReplacementID(
                            entityType: entityType,
                            retainedID: retainedID,
                            node: node,
                            resolutions: resolutions
                        ) != nil
                    }
            }
            .sorted { $0.key.uuidString < $1.key.uuidString }
        let duplicateRecordCount = duplicateGroups.reduce(0) { partial, group in
            partial + group.value.count - 1
        }
        var replacements: [PlannedReplacement] = []
        var candidates: [DuplicateCandidate] = []
        var unresolvedIssues: [PublicIDRepairUnresolvedReference] = []
        var usedIDs = Set(nodes.map { $0.readPublicID() })

        for (retainedID, duplicateNodes) in repairGroups {
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
            let establishedOwnerHerdID = selectedCrossHerdOwnerID(
                entityType: entityType,
                retainedID: retainedID,
                resolutions: resolutions
            )
            if entityType == .herd {
                let issue = duplicateHerdCanonicalIssue(
                    retainedID: retainedID,
                    entries: entries,
                    relationshipContextByLocalIdentifier: relationshipContextByLocalIdentifier
                )
                if let selectedStableIdentifier = resolutions[issue.id],
                   let selected = entries.first(where: {
                       $0.stableIdentifier == selectedStableIdentifier
                   }) {
                    selectedCanonicalLocalIdentifier = selected.node.localIdentifier
                } else {
                    unresolvedIssues.append(issue)
                }
            } else if let establishedOwnerHerdID {
                selectedCanonicalLocalIdentifier = entries.first {
                    $0.node.herdPublicID == establishedOwnerHerdID
                }?.node.localIdentifier
            }

            let defaultCanonicalLocalIdentifier = entries.first?.node.localIdentifier
            let canonicalLocalIdentifier: String?
            if entityType == .herd {
                canonicalLocalIdentifier = selectedCanonicalLocalIdentifier
                    ?? defaultCanonicalLocalIdentifier
            } else if establishedOwnerHerdID != nil {
                // A durable bridge owner is authoritative even when that owner's record is not
                // currently visible locally. In that case no local record may retain the old ID.
                canonicalLocalIdentifier = selectedCanonicalLocalIdentifier
            } else {
                canonicalLocalIdentifier = defaultCanonicalLocalIdentifier
            }
            let canonicalEntry = canonicalLocalIdentifier.flatMap { localIdentifier in
                entries.first { $0.node.localIdentifier == localIdentifier }
            }

            let herdGroups = Dictionary(grouping: entries.compactMap { entry -> (UUID, String)? in
                guard let herdPublicID = entry.node.herdPublicID else { return nil }
                return (herdPublicID, entry.node.localIdentifier)
            }, by: { $0.0 })
            let bridgeMappingLocalIdentifierByHerd = herdGroups.mapValues { values in
                values.first?.1
            }
            let visibleHerdIDs = Set(entries.compactMap { $0.node.herdPublicID })
            let canonicalHerdID = canonicalEntry?.node.herdPublicID
            let crossHerdOwnerID = establishedOwnerHerdID
                ?? (visibleHerdIDs.count > 1 ? canonicalHerdID : nil)

            for entry in entries {
                let retainsOriginalID = entry.node.localIdentifier == canonicalLocalIdentifier
                let resultingID: UUID
                var canApplyReplacement = true

                if retainsOriginalID {
                    resultingID = retainedID
                } else if let forcedID = forcedCrossHerdReplacementID(
                    entityType: entityType,
                    retainedID: retainedID,
                    node: entry.node,
                    resolutions: resolutions
                ),
                    entry.node.herdPublicID.flatMap({
                        bridgeMappingLocalIdentifierByHerd[$0] ?? nil
                    }) == entry.node.localIdentifier {
                    resultingID = forcedID
                    canApplyReplacement = reserveCrossHerdReplacementID(
                        forcedID,
                        retainedID: retainedID,
                        entityType: entityType,
                        recordDescription: entry.node.recordDescription,
                        stableRecordIdentifier: entry.stableIdentifier,
                        usedIDs: &usedIDs,
                        unresolvedIssues: &unresolvedIssues
                    )
                } else if let herdPublicID = entry.node.herdPublicID,
                          let crossHerdOwnerID,
                          herdPublicID != crossHerdOwnerID,
                          bridgeMappingLocalIdentifierByHerd[herdPublicID] == entry.node.localIdentifier {
                    let mappedID = publicIDRepairCrossHerdReplacementID(
                        entityType: entityType,
                        retainedPublicID: retainedID,
                        herdPublicID: herdPublicID
                    )
                    resultingID = mappedID
                    canApplyReplacement = reserveCrossHerdReplacementID(
                        mappedID,
                        retainedID: retainedID,
                        entityType: entityType,
                        recordDescription: entry.node.recordDescription,
                        stableRecordIdentifier: entry.stableIdentifier,
                        usedIDs: &usedIDs,
                        unresolvedIssues: &unresolvedIssues
                    )
                } else {
                    resultingID = makeReplacementID(
                        entityType: entityType,
                        retainedID: retainedID,
                        stableRecordIdentifier: entry.stableIdentifier,
                        usedIDs: &usedIDs
                    )
                }

                if !retainsOriginalID, canApplyReplacement {
                    replacements.append(
                        PlannedReplacement(
                            report: PublicIDRepairReplacement(
                                entityType: entityType,
                                recordDescription: entry.node.recordDescription,
                                stableRecordIdentifier: entry.stableIdentifier,
                                retainedPublicID: retainedID,
                                replacementPublicID: resultingID,
                                owningHerdPublicID: entry.node.herdPublicID,
                                recordFingerprint: entry.graphFingerprint,
                                retainedStableRecordIdentifier: canonicalEntry?.stableIdentifier,
                                retainedOwningHerdPublicID: canonicalEntry?.node.herdPublicID,
                                retainedRecordFingerprint: canonicalEntry?.graphFingerprint
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
                        herdPublicID: entry.node.herdPublicID,
                        stableRecordIdentifier: entry.stableIdentifier,
                        recordDescription: entry.node.recordDescription,
                        detail: semanticCandidateDetail(
                            node: entry.node,
                            relationshipContext: relationshipContextByLocalIdentifier[
                                entry.node.localIdentifier
                            ],
                            retainsOriginalID: retainsOriginalID
                        ),
                        retainedPublicID: retainedID,
                        resultingPublicID: canApplyReplacement ? resultingID : retainedID
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

    private func selectedCrossHerdOwnerID(
        entityType: PublicIDRepairEntityType,
        retainedID: UUID,
        resolutions: [String: String]
    ) -> UUID? {
        let key = PublicIDRepairCrossHerdDirective.ownerResolutionID(
            entityType: entityType,
            retainedPublicID: retainedID
        )
        guard let rawValue = resolutions[key] else { return nil }
        return UUID(uuidString: rawValue)
    }

    private func forcedCrossHerdReplacementID(
        entityType: PublicIDRepairEntityType,
        retainedID: UUID,
        node: AggregateNode,
        resolutions: [String: String]
    ) -> UUID? {
        guard let herdPublicID = node.herdPublicID else { return nil }
        let key = PublicIDRepairCrossHerdDirective.replacementResolutionID(
            entityType: entityType,
            retainedPublicID: retainedID,
            herdPublicID: herdPublicID
        )
        guard let rawValue = resolutions[key] else { return nil }
        return UUID(uuidString: rawValue)
    }

    private func reserveCrossHerdReplacementID(
        _ replacementID: UUID,
        retainedID: UUID,
        entityType: PublicIDRepairEntityType,
        recordDescription: String,
        stableRecordIdentifier: String,
        usedIDs: inout Set<UUID>,
        unresolvedIssues: inout [PublicIDRepairUnresolvedReference]
    ) -> Bool {
        guard usedIDs.insert(replacementID).inserted else {
            unresolvedIssues.append(
                PublicIDRepairUnresolvedReference(
                    kind: .canonicalRecord,
                    entityType: entityType,
                    recordDescription: recordDescription,
                    stableRecordIdentifier: stableRecordIdentifier,
                    fieldName: "publicID",
                    referencedPublicID: retainedID,
                    reason: "The durable cross-Herd replacement ID is already used by another local record. Repair remains blocked rather than merging two records onto the same public ID."
                )
            )
            return false
        }
        return true
    }

    private func duplicateHerdCanonicalIssue(
        retainedID: UUID,
        entries: [(node: AggregateNode, graphFingerprint: String, stableIdentifier: String)],
        relationshipContextByLocalIdentifier: [String: String]
    ) -> PublicIDRepairUnresolvedReference {
        let descriptionCounts = Dictionary(grouping: entries, by: {
            $0.node.recordDescription
        }).mapValues(\.count)

        return PublicIDRepairUnresolvedReference(
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
                let relationshipContext = relationshipContextByLocalIdentifier[
                    entry.node.localIdentifier
                ]
                let semanticContext = semanticCandidateChoiceContext(
                    node: entry.node,
                    relationshipContext: relationshipContext
                )
                let recordDescription: String
                if descriptionCounts[entry.node.recordDescription, default: 0] > 1 {
                    recordDescription = "\(entry.node.recordDescription) — \(semanticContext)"
                } else {
                    recordDescription = entry.node.recordDescription
                }
                return PublicIDRepairResolutionCandidate(
                    stableRecordIdentifier: entry.stableIdentifier,
                    recordDescription: recordDescription,
                    detail: "If selected, this Herd remains attached to the existing shared bridge. \(semanticCandidateDetail(node: entry.node, relationshipContext: relationshipContext, retainsOriginalID: true))",
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

    func makeReplacementID(
        entityType: PublicIDRepairEntityType,
        retainedID: UUID,
        stableRecordIdentifier: String,
        usedIDs: inout Set<UUID>
    ) -> UUID {
        var attempt = 0
        while true {
            let candidate = publicIDRepairDeterministicReplacementID(
                entityType: entityType,
                originalPublicID: retainedID,
                portableRecordIdentity: stableRecordIdentifier,
                attempt: attempt
            )
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
