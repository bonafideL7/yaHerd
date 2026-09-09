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
        var grouped: [UUID: [AggregateNode]] = [:]
        for node in nodes {
            grouped[node.readPublicID(), default: []].append(node)
        }

        var duplicateGroupIDs: [UUID] = []
        var repairGroupIDs: [UUID] = []
        var duplicateRecordCount = 0
        for (retainedID, groupedNodes) in grouped {
            if groupedNodes.count > 1 {
                duplicateGroupIDs.append(retainedID)
                duplicateRecordCount += groupedNodes.count - 1
            }

            var requiresRepair = groupedNodes.count > 1
            if !requiresRepair {
                for node in groupedNodes {
                    if forcedCrossHerdReplacementID(
                        entityType: entityType,
                        retainedID: retainedID,
                        node: node,
                        resolutions: resolutions
                    ) != nil {
                        requiresRepair = true
                        break
                    }
                }
            }
            if requiresRepair {
                repairGroupIDs.append(retainedID)
            }
        }
        duplicateGroupIDs.sort { $0.uuidString < $1.uuidString }
        repairGroupIDs.sort { $0.uuidString < $1.uuidString }

        var replacements: [PlannedReplacement] = []
        var candidates: [DuplicateCandidate] = []
        var unresolvedIssues: [PublicIDRepairUnresolvedReference] = []
        var usedIDs = Set<UUID>()
        usedIDs.reserveCapacity(nodes.count)
        for node in nodes {
            usedIDs.insert(node.readPublicID())
        }

        for retainedID in repairGroupIDs {
            guard let duplicateNodes = grouped[retainedID] else { continue }

            var metadata: CollaborationRevisionMetadata?
            if let firstNode = duplicateNodes.first {
                metadata = revisionMetadata[
                    CollaborationAggregateKey(
                        type: firstNode.collaborationType,
                        publicID: retainedID
                    )
                ]
            }

            var nodeByCanonicalKey: [String: AggregateNode] = [:]
            var canonicalKeyCollision = false
            for node in duplicateNodes {
                let key = canonicalSortKey(
                    node: node,
                    metadata: metadata,
                    graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier
                )
                if nodeByCanonicalKey[key] != nil {
                    canonicalKeyCollision = true
                } else {
                    nodeByCanonicalKey[key] = node
                }
            }
            guard !canonicalKeyCollision else {
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

            let orderedCanonicalKeys = nodeByCanonicalKey.keys.sorted()
            var entries: [(node: AggregateNode, graphFingerprint: String, stableIdentifier: String)] = []
            entries.reserveCapacity(orderedCanonicalKeys.count)
            for (ordinal, canonicalKey) in orderedCanonicalKeys.enumerated() {
                guard let node = nodeByCanonicalKey[canonicalKey] else { continue }
                let graphFingerprint = graphFingerprintByLocalIdentifier[node.localIdentifier] ?? ""
                let stableIdentifier = duplicateCandidateIdentifier(
                    entityType: entityType,
                    retainedID: retainedID,
                    snapshotKey: node.snapshotKey,
                    graphFingerprint: graphFingerprint,
                    ordinal: ordinal
                )
                entries.append(
                    (
                        node: node,
                        graphFingerprint: graphFingerprint,
                        stableIdentifier: stableIdentifier
                    )
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
                if let selectedStableIdentifier = resolutions[issue.id] {
                    for entry in entries {
                        if entry.stableIdentifier == selectedStableIdentifier {
                            selectedCanonicalLocalIdentifier = entry.node.localIdentifier
                            break
                        }
                    }
                }
                if selectedCanonicalLocalIdentifier == nil {
                    unresolvedIssues.append(issue)
                }
            } else if let establishedOwnerHerdID {
                for entry in entries {
                    if entry.node.herdPublicID == establishedOwnerHerdID {
                        selectedCanonicalLocalIdentifier = entry.node.localIdentifier
                        break
                    }
                }
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

            var canonicalEntry: (node: AggregateNode, graphFingerprint: String, stableIdentifier: String)?
            if let canonicalLocalIdentifier {
                for entry in entries {
                    if entry.node.localIdentifier == canonicalLocalIdentifier {
                        canonicalEntry = entry
                        break
                    }
                }
            }

            var bridgeMappingLocalIdentifierByHerd: [UUID: String] = [:]
            var visibleHerdIDs = Set<UUID>()
            for entry in entries {
                guard let herdPublicID = entry.node.herdPublicID else { continue }
                visibleHerdIDs.insert(herdPublicID)
                if bridgeMappingLocalIdentifierByHerd[herdPublicID] == nil {
                    bridgeMappingLocalIdentifierByHerd[herdPublicID] = entry.node.localIdentifier
                }
            }
            let canonicalHerdID = canonicalEntry?.node.herdPublicID
            let crossHerdOwnerID = establishedOwnerHerdID
                ?? (visibleHerdIDs.count > 1 ? canonicalHerdID : nil)

            for entry in entries {
                let retainsOriginalID = entry.node.localIdentifier == canonicalLocalIdentifier
                let resultingID: UUID
                var canApplyReplacement = true

                let entryHerdPublicID = entry.node.herdPublicID
                let isBridgeMappingForEntry: Bool
                if let entryHerdPublicID {
                    isBridgeMappingForEntry = bridgeMappingLocalIdentifierByHerd[entryHerdPublicID]
                        == entry.node.localIdentifier
                } else {
                    isBridgeMappingForEntry = false
                }

                if retainsOriginalID {
                    resultingID = retainedID
                } else if let forcedID = forcedCrossHerdReplacementID(
                    entityType: entityType,
                    retainedID: retainedID,
                    node: entry.node,
                    resolutions: resolutions
                ), isBridgeMappingForEntry {
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
                } else if let herdPublicID = entryHerdPublicID,
                          let crossHerdOwnerID,
                          herdPublicID != crossHerdOwnerID,
                          isBridgeMappingForEntry {
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
                duplicateGroupCount: duplicateGroupIDs.count,
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
        var descriptionCounts: [String: Int] = [:]
        for entry in entries {
            descriptionCounts[entry.node.recordDescription, default: 0] += 1
        }

        var resolutionCandidates: [PublicIDRepairResolutionCandidate] = []
        resolutionCandidates.reserveCapacity(entries.count)
        for entry in entries {
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
            resolutionCandidates.append(
                PublicIDRepairResolutionCandidate(
                    stableRecordIdentifier: entry.stableIdentifier,
                    recordDescription: recordDescription,
                    detail: "If selected, this Herd remains attached to the existing shared bridge. \(semanticCandidateDetail(node: entry.node, relationshipContext: relationshipContext, retainsOriginalID: true))",
                    resultingPublicID: retainedID
                )
            )
        }

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
            candidates: resolutionCandidates
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
            let metadata = record.metadata
            guard let existing = result[key] else {
                result[key] = metadata
                continue
            }

            let shouldReplace: Bool
            if metadata.revision > existing.revision {
                shouldReplace = true
            } else if metadata.revision < existing.revision {
                shouldReplace = false
            } else if metadata.modifiedAt > existing.modifiedAt {
                shouldReplace = true
            } else if metadata.modifiedAt < existing.modifiedAt {
                shouldReplace = false
            } else {
                let currentSnapshotKey = stableSnapshotKey(metadata.currentFieldValues)
                let existingSnapshotKey = stableSnapshotKey(existing.currentFieldValues)
                shouldReplace = currentSnapshotKey < existingSnapshotKey
            }

            if shouldReplace {
                result[key] = metadata
            }
        }
        return result
    }
}
