import Foundation

private let publicIDRepairClearReferencePrefix = "bridge-clear-reference|"

extension HerdSharingBridgeStoreSnapshot {
    /// Adds a terminal Diagnostics choice for bridge-only, non-ownership references that cannot
    /// resolve to an entity in this Herd. The existing translator remains authoritative for all
    /// normal identity choices; this wrapper only narrows non-ownership choices to same-Herd
    /// targets and handles the otherwise candidate-less case.
    func preparingForPublicIDRepairImportWithInvalidReferenceRecovery(
        report: PublicIDRepairReport,
        localRepairedSnapshot: HerdSharingBridgeStoreSnapshot
    ) throws -> HerdSharingBridgeStoreSnapshot {
        let persistedClearKeys = publicIDRepairPersistedClearKeys(report: report)
        if !persistedClearKeys.isEmpty {
            let clearedSnapshot = clearingPublicIDRepairReferences(persistedClearKeys)
            return try clearedSnapshot.preparingForPublicIDRepairImport(
                report: report,
                localRepairedSnapshot: localRepairedSnapshot
            )
        }

        do {
            return try preparingForPublicIDRepairImport(
                report: report,
                localRepairedSnapshot: localRepairedSnapshot
            )
        } catch let required as PublicIDRepairBridgeResolutionRequired {
            var augmentedIssues: [PublicIDRepairUnresolvedReference] = []

            for issue in required.issues {
                guard let source = publicIDRepairBridgeReferenceSource(for: issue),
                      let targetEntityType = publicIDRepairReferencedEntityType(
                          entityName: source.entityName,
                          attributeName: issue.fieldName
                      ),
                      publicIDRepairOwnershipBearingReferencedStep(
                          entityName: source.entityName,
                          attributeName: issue.fieldName
                      ) == nil else {
                    augmentedIssues.append(issue)
                    continue
                }

                let sameHerdCandidates = publicIDRepairSameHerdCandidates(
                    issue.candidates,
                    targetEntityType: targetEntityType,
                    localRepairedSnapshot: localRepairedSnapshot
                )
                if !sameHerdCandidates.isEmpty {
                    augmentedIssues.append(
                        PublicIDRepairUnresolvedReference(
                            kind: issue.kind,
                            entityType: issue.entityType,
                            recordDescription: issue.recordDescription,
                            stableRecordIdentifier: issue.stableRecordIdentifier,
                            fieldName: issue.fieldName,
                            referencedPublicID: issue.referencedPublicID,
                            reason: "This shared record exists only in the bridge and references a repaired duplicate public ID. Choose a repaired target that belongs to this Herd.",
                            candidates: sameHerdCandidates,
                            bridgeParticipantHerdPublicIDs: issue.bridgeParticipantHerdPublicIDs
                        )
                    )
                    continue
                }

                let markedStableID = publicIDRepairClearReferenceStableID(
                    entityName: source.entityName,
                    recordPublicID: source.recordPublicID
                )
                let clearCandidate = PublicIDRepairResolutionCandidate(
                    stableRecordIdentifier: [
                        "bridge-clear-reference-candidate",
                        source.entityName,
                        source.recordPublicID,
                        issue.fieldName,
                    ].joined(separator: "|"),
                    recordDescription: "Remove invalid shared reference",
                    detail: "No repaired target exists in this Herd. Removing this stored reference prevents the shared record from linking to a record owned by another Herd.",
                    resultingPublicID: issue.referencedPublicID
                )
                augmentedIssues.append(
                    PublicIDRepairUnresolvedReference(
                        kind: issue.kind,
                        entityType: issue.entityType,
                        recordDescription: issue.recordDescription,
                        stableRecordIdentifier: markedStableID,
                        fieldName: issue.fieldName,
                        referencedPublicID: issue.referencedPublicID,
                        reason: "This shared record references a repaired public ID, but no valid target exists in this Herd. Remove the invalid shared reference to continue without creating a cross-Herd relationship.",
                        candidates: [clearCandidate],
                        bridgeParticipantHerdPublicIDs: issue.bridgeParticipantHerdPublicIDs
                    )
                )
            }

            throw PublicIDRepairBridgeResolutionRequired(
                issues: augmentedIssues.sorted { $0.id < $1.id }
            )
        }
    }

    private func publicIDRepairPersistedClearKeys(
        report: PublicIDRepairReport
    ) -> Set<PublicIDRepairInvalidReferenceKey> {
        Set(report.referenceUpdates.compactMap { update in
            guard update.stableRecordIdentifier.hasPrefix(publicIDRepairClearReferencePrefix),
                  update.previousPublicID == update.repairedPublicID,
                  let source = publicIDRepairMarkedReferenceSource(
                      stableRecordIdentifier: update.stableRecordIdentifier
                  ) else {
                return nil
            }
            return PublicIDRepairInvalidReferenceKey(
                entityName: source.entityName,
                recordPublicID: source.recordPublicID,
                fieldName: update.fieldName
            )
        })
    }

    private func publicIDRepairSameHerdCandidates(
        _ candidates: [PublicIDRepairResolutionCandidate],
        targetEntityType: PublicIDRepairEntityType,
        localRepairedSnapshot: HerdSharingBridgeStoreSnapshot
    ) -> [PublicIDRepairResolutionCandidate] {
        guard let targetStep = publicIDRepairBridgeStep(for: targetEntityType) else {
            return []
        }
        let candidateIDs = Set(candidates.map(\.resultingPublicID))
        let sameHerdIDs = Set(
            localRepairedSnapshot.records(for: targetStep).compactMap { record -> UUID? in
                guard let publicID = record.parsedPublicID,
                      candidateIDs.contains(publicID),
                      case .string(let rawOwnerID) = record.attributes["herdPublicID"],
                      UUID(uuidString: rawOwnerID) == herdPublicID else {
                    return nil
                }
                return publicID
            }
        )
        return candidates.filter { sameHerdIDs.contains($0.resultingPublicID) }
    }

    private func clearingPublicIDRepairReferences(
        _ keys: Set<PublicIDRepairInvalidReferenceKey>
    ) -> HerdSharingBridgeStoreSnapshot {
        var updated = recordsByStep
        for step in HerdSharingBridgeStep.entitySteps where step != .deletions {
            updated[step] = updated[step, default: []].map { record in
                let matchingFields = keys.filter {
                    $0.entityName == record.entityName
                        && $0.recordPublicID == record.publicID.lowercased()
                }.map(\.fieldName)
                guard !matchingFields.isEmpty else { return record }

                var attributes = record.attributes
                var changed = false
                for fieldName in matchingFields where attributes[fieldName] != nil {
                    attributes[fieldName] = .null
                    changed = true
                }
                guard changed else { return record }
                return HerdSharingBridgeRecordSnapshot(
                    entityName: record.entityName,
                    publicID: record.publicID,
                    sourceObjectURI: record.sourceObjectURI,
                    attributes: attributes
                )
            }
        }
        return HerdSharingBridgeStoreSnapshot(
            herdPublicID: herdPublicID,
            storeDescription: storeDescription,
            recordsByStep: updated
        )
    }
}

private struct PublicIDRepairInvalidReferenceKey: Hashable {
    let entityName: String
    let recordPublicID: String
    let fieldName: String
}

private struct PublicIDRepairBridgeReferenceSource {
    let entityName: String
    let recordPublicID: String
}

private func publicIDRepairBridgeReferenceSource(
    for issue: PublicIDRepairUnresolvedReference
) -> PublicIDRepairBridgeReferenceSource? {
    let components = issue.stableRecordIdentifier.split(separator: "|", omittingEmptySubsequences: false)
    guard components.count == 3,
          components[0] == "bridge" else {
        return nil
    }
    return PublicIDRepairBridgeReferenceSource(
        entityName: String(components[1]),
        recordPublicID: String(components[2]).lowercased()
    )
}

private func publicIDRepairMarkedReferenceSource(
    stableRecordIdentifier: String
) -> PublicIDRepairBridgeReferenceSource? {
    guard stableRecordIdentifier.hasPrefix(publicIDRepairClearReferencePrefix) else {
        return nil
    }
    let remainder = stableRecordIdentifier.dropFirst(publicIDRepairClearReferencePrefix.count)
    let components = remainder.split(separator: "|", omittingEmptySubsequences: false)
    guard components.count == 2 else { return nil }
    return PublicIDRepairBridgeReferenceSource(
        entityName: String(components[0]),
        recordPublicID: String(components[1]).lowercased()
    )
}

private func publicIDRepairClearReferenceStableID(
    entityName: String,
    recordPublicID: String
) -> String {
    "\(publicIDRepairClearReferencePrefix)\(entityName)|\(recordPublicID.lowercased())"
}
