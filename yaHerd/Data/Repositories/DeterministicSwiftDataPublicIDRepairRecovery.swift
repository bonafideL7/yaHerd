import Foundation
import SwiftData

extension DeterministicSwiftDataPublicIDRepairService: PublicIDRepairTransactionalRecovering {
    private struct RecoveryMutation {
        let state: PublicIDRepairRecoveryTransformationState
        let canRestoreFromBackup: Bool
        let applyFinal: () -> Void
        let applyBackup: () -> Void
        let description: String
        let evidence: PublicIDRepairRecoveryEvidence
    }

    private struct TreatmentItemRecoveryMatch {
        let location: TreatmentItemLocation
        let backupItem: BackupTreatmentItem
    }

    private struct RecoveryPlan {
        let backup: PublicIDRepairBackup
        let mutations: [RecoveryMutation]
        let manualResolutionIssues: [PublicIDRepairUnresolvedReference]

        var assessment: PublicIDRepairIndeterminateRecoveryAssessment {
            let states = mutations.map(\.state)
            let contradictory = mutations.filter {
                $0.state == .contradictoryOrAmbiguous
            }
            let capability: PublicIDRepairIndeterminateRecoveryCapability
            if contradictory.isEmpty {
                capability = .manifestForwardRecoveryAvailable
            } else if manualResolutionIssues.isEmpty
                        && contradictory.allSatisfy(\.canRestoreFromBackup) {
                capability = .verifiedBackupRestoreAvailable
            } else {
                capability = .manualRecoveryResolutionRequired
            }
            return PublicIDRepairIndeterminateRecoveryAssessment(
                transformationStates: states,
                capability: capability,
                blockingReason: contradictory.first?.description,
                evidence: mutations.map(\.evidence),
                manualResolutionIssues: manualResolutionIssues
            )
        }
    }

    func assessIndeterminateRecovery(
        for report: PublicIDRepairReport
    ) throws -> PublicIDRepairIndeterminateRecoveryAssessment {
        try makeRecoveryPlan(for: report).assessment
    }

    func recoverIndeterminateRepair(
        report: PublicIDRepairReport,
        action: PublicIDRepairRecoveryChoice,
        willCommit: PublicIDRepairWillCommit,
        didCommit: PublicIDRepairDidCommit
    ) async throws -> PublicIDRepairReport {
        let initialPlan = try makeRecoveryPlan(for: report)
        let initialAssessment = initialPlan.assessment

        switch action {
        case .continueManifestRepair:
            guard initialAssessment.canContinueManifestRepair else {
                throw PublicIDRepairRecoveryError.invalidChoice
            }
            return try await applyForwardRecovery(
                from: report,
                plan: initialPlan,
                action: action,
                willCommit: willCommit,
                didCommit: didCommit
            )

        case .restorePreRepairBackup:
            guard initialAssessment.requiresBackupRestore else {
                throw PublicIDRepairRecoveryError.invalidChoice
            }

            // Persist the destructive recovery choice and a snapshot of the current damaged
            // repair boundary before restoring the backup bound to this pending generation.
            let currentLoaded = try loadRecords()
            let damagedBackupURL = try createRecoveryBoundaryBackup(
                loaded: currentLoaded,
                sourceBackup: initialPlan.backup,
                report: report
            )
            let damagedBackup = PublicIDRepairBackupReference(
                filename: damagedBackupURL.lastPathComponent,
                path: damagedBackupURL.path
            )
            let restorationManifest = report.manifest.appendingLocalRecoveryGeneration(
                completedAt: .now,
                backup: damagedBackup,
                action: .restorePreRepairBackup,
                validationPassed: nil
            )
            let restorationReport = reportWithManifest(
                report,
                manifest: restorationManifest,
                backup: damagedBackup
            )
            try await willCommit(restorationReport)

            try await restoreRepairBoundary(
                plan: initialPlan,
                report: report,
                didCommit: didCommit
            )
            try verifyBackupBoundary(report: report)

            // Restoration is not terminal and never deletes the journal. Re-evaluate the exact
            // restored generation baseline, then replay only manifest transformations that are
            // still missing. A second fresh backup precedes that new local mutation generation.
            let restoredPlan = try makeRecoveryPlan(for: report)
            guard restoredPlan.assessment.canContinueManifestRepair else {
                throw PublicIDRepairRecoveryError.restorationVerificationFailed(
                    restoredPlan.assessment.blockingReason
                        ?? "The restored graph still cannot be matched uniquely to the manifest."
                )
            }
            return try await applyForwardRecovery(
                from: restorationReport,
                plan: restoredPlan,
                action: .continueManifestRepair,
                willCommit: willCommit,
                didCommit: didCommit
            )
        }
    }

    func resolveIndeterminateRecovery(
        report: PublicIDRepairReport,
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit,
        didCommit: PublicIDRepairDidCommit
    ) async throws -> PublicIDRepairReport {
        let initialPlan = try makeRecoveryPlan(for: report)
        guard initialPlan.assessment.requiresManualResolution else {
            throw PublicIDRepairRecoveryError.invalidChoice
        }

        let selectableIssues = initialPlan.manualResolutionIssues.filter {
            !$0.candidates.isEmpty
        }
        guard selectableIssues.count == initialPlan.manualResolutionIssues.count else {
            throw PublicIDRepairError.unresolvedReferences(
                initialPlan.manualResolutionIssues
            )
        }
        let selectedByIssueID = try validatedResolutionMap(resolutions)
        var markers: [String] = []
        for issue in selectableIssues {
            guard let selectedCandidateID = selectedByIssueID[issue.id],
                  issue.candidates.contains(where: {
                      $0.stableRecordIdentifier == selectedCandidateID
                  }) else {
                throw PublicIDRepairError.unresolvedReferences(
                    initialPlan.manualResolutionIssues
                )
            }
            markers.append(
                PublicIDRepairRecoverySelection.manualBindingMarker(
                    issueID: issue.id,
                    candidateStableRecordIdentifier: selectedCandidateID
                )
            )
        }

        // The binding is durable before it can influence a local mutation. It changes neither the
        // manifest's public-ID authority nor the current backup reference.
        let decisionManifest = report.manifest.appendingLocalRecoveryResolutionGeneration(
            completedAt: .now,
            selectedResolutionIDs: markers
        )
        let currentBackup = PublicIDRepairBackupReference(
            filename: report.backupFilename,
            path: report.backupPath
        )
        let decisionReport = reportWithManifest(
            report,
            manifest: decisionManifest,
            backup: currentBackup
        )
        try await willCommit(decisionReport)

        let reboundPlan = try makeRecoveryPlan(for: decisionReport)
        guard reboundPlan.assessment.canContinueManifestRepair else {
            if reboundPlan.assessment.requiresManualResolution {
                throw PublicIDRepairError.unresolvedReferences(
                    reboundPlan.manualResolutionIssues
                )
            }
            throw PublicIDRepairRecoveryError.invalidChoice
        }

        return try await applyForwardRecovery(
            from: decisionReport,
            plan: reboundPlan,
            action: .continueManifestRepair,
            willCommit: willCommit,
            didCommit: didCommit
        )
    }

    private func applyForwardRecovery(
        from report: PublicIDRepairReport,
        plan: RecoveryPlan,
        action: PublicIDRepairRecoveryChoice,
        willCommit: PublicIDRepairWillCommit,
        didCommit: PublicIDRepairDidCommit
    ) async throws -> PublicIDRepairReport {
        let missing = plan.mutations.filter { $0.state == .definitelyNotApplied }
        if missing.isEmpty {
            try verifyManifestBoundary(report)
            return report
        }

        let loaded = try loadRecords()
        let backupURL = try createRecoveryBoundaryBackup(
            loaded: loaded,
            sourceBackup: plan.backup,
            report: report
        )
        let backupReference = PublicIDRepairBackupReference(
            filename: backupURL.lastPathComponent,
            path: backupURL.path
        )
        let manifest = report.manifest.appendingLocalRecoveryGeneration(
            completedAt: .now,
            backup: backupReference,
            action: action,
            validationPassed: nil
        )
        let plannedReport = reportWithManifest(
            report,
            manifest: manifest,
            backup: backupReference
        )

        // The new boundary backup has completed its durable file write before the journal can
        // reference this generation. No local mutation occurs before both boundaries succeed.
        try await willCommit(plannedReport)

        do {
            for mutation in missing {
                mutation.applyFinal()
            }
            let repairedLoaded = try loadRecords()
            try synchronizeRevisionRecords(loaded: repairedLoaded)
            let issues = try validationIssues(
                loaded: repairedLoaded,
                replacements: [],
                referenceUpdates: []
            )
            guard issues.isEmpty else {
                throw PublicIDRepairError.validationFailed(issues)
            }
            try verifyManifestBoundary(plannedReport)

            try PersistenceLog.save(
                modelContext,
                operation: "DeterministicSwiftDataPublicIDRepairService.recoverIndeterminateRepair"
            )
            registerCurrentRevisionMetadata(repairedLoaded.allAggregates)
            await didCommit()

            let validatedManifest = replacingLatestValidation(
                in: plannedReport.manifest,
                with: true
            )
            return reportWithManifest(
                plannedReport,
                manifest: validatedManifest,
                backup: backupReference
            )
        } catch {
            modelContext.rollback()
            ReliabilityLog.persistenceFailure(
                "DeterministicSwiftDataPublicIDRepairService.recoverIndeterminateRepair",
                error: error
            )
            throw error
        }
    }

    private func makeRecoveryPlan(
        for report: PublicIDRepairReport
    ) throws -> RecoveryPlan {
        guard report.manifest.contradictions.isEmpty else {
            throw PublicIDRepairRecoveryError.manifestContradiction(
                report.manifest.contradictions.joined(separator: " ")
            )
        }
        let backup = try loadBoundBackup(for: report)
        let loaded = try loadRecords()
        let nodes = makeAggregateNodes(loaded: loaded)
        let treatmentLocations = makeTreatmentItemLocations(loaded: loaded)
        let localMappings = report.manifest.recordMappings.filter {
            $0.origin == .localSwiftData
        }
        let localReferences = report.manifest.referenceTransformations.filter {
            $0.origin == .localSwiftData && $0.sourceEntityType != nil
        }
        let persistedBindings = PublicIDRepairRecoverySelection.manualBindings(
            in: report.manifest
        )

        var mutations: [RecoveryMutation] = []
        var manualResolutionIssues: [PublicIDRepairUnresolvedReference] = []
        var nodeByPortableIdentity: [String: AggregateNode] = [:]
        var manuallyBoundStableIDs: Set<String> = []
        var unavailableAggregateStableIDs: Set<String> = []

        let requiredStableIDs = Set(
            localMappings.map(\.portableRecordIdentity)
                + localReferences.map(\.sourcePortableRecordIdentity)
        )
        var backupByStableID: [String: BackupAggregate] = [:]
        var strictMatchesByStableID: [String: [AggregateNode]] = [:]
        for stableID in requiredStableIDs.sorted() {
            guard let backupAggregate = backup.aggregates.first(where: {
                $0.stableRecordIdentifier == stableID
            }) else {
                continue
            }
            backupByStableID[stableID] = backupAggregate
            strictMatchesByStableID[stableID] = matchingNodes(
                for: backupAggregate,
                stableRecordIdentifier: stableID,
                nodes: nodes,
                report: report
            )
        }
        let claimedExactLocalIDs = Set(
            strictMatchesByStableID.values.compactMap { matches in
                matches.count == 1 ? matches.first?.localIdentifier : nil
            }
        )

        for stableID in requiredStableIDs.sorted() {
            guard let backupAggregate = backupByStableID[stableID] else { continue }
            let exactMatches = strictMatchesByStableID[stableID] ?? []
            if exactMatches.count == 1, let matched = exactMatches.first {
                nodeByPortableIdentity[stableID] = matched
                continue
            }

            let plausible = plausibleRecoveryNodes(
                for: backupAggregate,
                nodes: nodes,
                report: report
            ).filter { !claimedExactLocalIDs.contains($0.localIdentifier) }
            let issue = manualRecoveryIssue(
                backupAggregate: backupAggregate,
                manifestStableIdentifier: stableID,
                plausibleNodes: plausible,
                report: report
            )

            if let selectedCandidateID = persistedBindings[issue.id] {
                let selectedMatches = plausible.filter {
                    manualRecoveryCandidateIdentifier(
                        node: $0,
                        manifestStableIdentifier: stableID,
                        report: report
                    ) == selectedCandidateID
                }
                if selectedMatches.count == 1, let selected = selectedMatches.first {
                    nodeByPortableIdentity[stableID] = selected
                    manuallyBoundStableIDs.insert(stableID)
                    continue
                }
            }

            unavailableAggregateStableIDs.insert(stableID)
            manualResolutionIssues.append(issue)
            let evidenceKind: PublicIDRepairRecoveryEvidenceKind
            if plausible.isEmpty {
                evidenceKind = .recordAppearsMissing
            } else if plausible.count == 1 {
                evidenceKind = .recordNoLongerUniquelyMatchesBackup
            } else {
                evidenceKind = .multiplePlausibleCurrentRecords
            }
            mutations.append(
                RecoveryMutation(
                    state: .contradictoryOrAmbiguous,
                    canRestoreFromBackup: false,
                    applyFinal: {},
                    applyBackup: {},
                    description: issue.reason,
                    evidence: PublicIDRepairRecoveryEvidence(
                        stableRecordIdentifier: stableID,
                        kind: evidenceKind,
                        description: issue.reason
                    )
                )
            )
        }

        for mapping in localMappings.sorted(by: { $0.id < $1.id }) {
            if let node = nodeByPortableIdentity[mapping.portableRecordIdentity],
               let backupAggregate = backupByStableID[mapping.portableRecordIdentity] {
                let current = node.readPublicID()
                let baseline = backupAggregate.publicID
                let wasManuallyBound = manuallyBoundStableIDs.contains(
                    mapping.portableRecordIdentity
                )
                let state: PublicIDRepairRecoveryTransformationState
                let evidenceKind: PublicIDRepairRecoveryEvidenceKind
                if current == mapping.finalPublicID {
                    state = .alreadyApplied
                    evidenceKind = wasManuallyBound
                        ? .recordNoLongerUniquelyMatchesBackup
                        : .matchedSafelyToBackup
                } else if wasManuallyBound {
                    state = .definitelyNotApplied
                    evidenceKind = .repairOwnedValueChangedOnIdentifiableRecord
                } else if baseline != mapping.finalPublicID && current == baseline {
                    state = .definitelyNotApplied
                    evidenceKind = .matchedSafelyToBackup
                } else {
                    state = .contradictoryOrAmbiguous
                    evidenceKind = .repairOwnedValueChangedOnIdentifiableRecord
                }
                let description = state == .contradictoryOrAmbiguous
                    ? "Manifest mapping for \(mapping.recordDescription) is in neither its bound-generation backup state nor its authoritative final state, but the same record is still uniquely identifiable."
                    : "Manifest mapping for \(mapping.recordDescription) is bound to one current record."
                mutations.append(
                    RecoveryMutation(
                        state: state,
                        canRestoreFromBackup: true,
                        applyFinal: { node.assignPublicID(mapping.finalPublicID) },
                        applyBackup: { node.assignPublicID(baseline) },
                        description: description,
                        evidence: PublicIDRepairRecoveryEvidence(
                            stableRecordIdentifier: mapping.portableRecordIdentity,
                            kind: evidenceKind,
                            description: description
                        )
                    )
                )
                continue
            }

            if unavailableAggregateStableIDs.contains(mapping.portableRecordIdentity) {
                continue
            }
            if let treatmentMutation = treatmentItemRecoveryMutation(
                mapping: mapping,
                backup: backup,
                locations: treatmentLocations,
                report: report
            ) {
                mutations.append(treatmentMutation)
            } else if !mapping.retainedOriginalID {
                let description = isTreatmentItemManifestMapping(mapping)
                    ? "Manifest treatment-item mapping \(mapping.portableRecordIdentity) cannot be located uniquely."
                    : "Manifest mapping \(mapping.portableRecordIdentity) is not represented in the bound backup."
                mutations.append(
                    RecoveryMutation(
                        state: .contradictoryOrAmbiguous,
                        canRestoreFromBackup: false,
                        applyFinal: {},
                        applyBackup: {},
                        description: description,
                        evidence: PublicIDRepairRecoveryEvidence(
                            stableRecordIdentifier: mapping.portableRecordIdentity,
                            kind: .manifestEvidenceContradiction,
                            description: description
                        )
                    )
                )
            }
        }

        for transformation in localReferences.sorted(by: { $0.id < $1.id }) {
            guard let node = nodeByPortableIdentity[transformation.sourcePortableRecordIdentity],
                  let backupAggregate = backupByStableID[transformation.sourcePortableRecordIdentity],
                  let baseline = backupRepairReference(
                      fieldName: transformation.fieldName,
                      aggregate: backupAggregate
                  ),
                  let current = readRepairReference(
                    fieldName: transformation.fieldName,
                    aggregate: node.aggregate
                  ) else {
                if unavailableAggregateStableIDs.contains(
                    transformation.sourcePortableRecordIdentity
                ) {
                    continue
                }
                let description = "Reference \(transformation.fieldName) on \(transformation.sourcePortableRecordIdentity) cannot be bound uniquely to the pending generation backup."
                mutations.append(
                    RecoveryMutation(
                        state: .contradictoryOrAmbiguous,
                        canRestoreFromBackup: false,
                        applyFinal: {},
                        applyBackup: {},
                        description: description,
                        evidence: PublicIDRepairRecoveryEvidence(
                            stableRecordIdentifier: transformation.sourcePortableRecordIdentity,
                            kind: .manifestEvidenceContradiction,
                            description: description
                        )
                    )
                )
                continue
            }

            if transformation.fieldName == "treatmentItemID", baseline == nil {
                let description = "The non-optional treatmentItemID reference is nil in the pending generation backup."
                mutations.append(
                    RecoveryMutation(
                        state: .contradictoryOrAmbiguous,
                        canRestoreFromBackup: false,
                        applyFinal: {},
                        applyBackup: {},
                        description: description,
                        evidence: PublicIDRepairRecoveryEvidence(
                            stableRecordIdentifier: transformation.sourcePortableRecordIdentity,
                            kind: .manifestEvidenceContradiction,
                            description: description
                        )
                    )
                )
                continue
            }

            let wasManuallyBound = manuallyBoundStableIDs.contains(
                transformation.sourcePortableRecordIdentity
            )
            let state: PublicIDRepairRecoveryTransformationState
            let evidenceKind: PublicIDRepairRecoveryEvidenceKind
            if current == transformation.finalPublicID {
                state = .alreadyApplied
                evidenceKind = wasManuallyBound
                    ? .recordNoLongerUniquelyMatchesBackup
                    : .matchedSafelyToBackup
            } else if wasManuallyBound {
                state = .definitelyNotApplied
                evidenceKind = .repairOwnedValueChangedOnIdentifiableRecord
            } else if baseline != transformation.finalPublicID && current == baseline {
                state = .definitelyNotApplied
                evidenceKind = .matchedSafelyToBackup
            } else {
                state = .contradictoryOrAmbiguous
                evidenceKind = .repairOwnedValueChangedOnIdentifiableRecord
            }
            let description = state == .contradictoryOrAmbiguous
                ? "Reference \(transformation.fieldName) is in neither its bound-generation backup state nor its manifest-authorized final state, but its source record is still uniquely identifiable."
                : "Reference \(transformation.fieldName) is bound to one current source record."
            mutations.append(
                RecoveryMutation(
                    state: state,
                    canRestoreFromBackup: true,
                    applyFinal: {
                        self.assignRepairReference(
                            transformation.finalPublicID,
                            fieldName: transformation.fieldName,
                            aggregate: node.aggregate
                        )
                    },
                    applyBackup: {
                        self.assignRepairReference(
                            baseline,
                            fieldName: transformation.fieldName,
                            aggregate: node.aggregate
                        )
                    },
                    description: description,
                    evidence: PublicIDRepairRecoveryEvidence(
                        stableRecordIdentifier: transformation.sourcePortableRecordIdentity,
                        kind: evidenceKind,
                        description: description
                    )
                )
            )
        }

        return RecoveryPlan(
            backup: backup,
            mutations: mutations,
            manualResolutionIssues: manualResolutionIssues.sorted { $0.id < $1.id }
        )
    }

    private func plausibleRecoveryNodes(
        for backup: BackupAggregate,
        nodes: [AggregateNode],
        report: PublicIDRepairReport
    ) -> [AggregateNode] {
        let expectedOwner = normalizedOriginalPublicID(
            backup.herdPublicID,
            entityType: .herd,
            report: report
        )
        return nodes.filter { node in
            node.entityType == backup.entityType
                && normalizedOriginalPublicID(
                    node.herdPublicID,
                    entityType: .herd,
                    report: report
                ) == expectedOwner
        }
    }

    private func manualRecoveryIssue(
        backupAggregate: BackupAggregate,
        manifestStableIdentifier: String,
        plausibleNodes: [AggregateNode],
        report: PublicIDRepairReport
    ) -> PublicIDRepairUnresolvedReference {
        let candidateIDs = plausibleNodes.map {
            manualRecoveryCandidateIdentifier(
                node: $0,
                manifestStableIdentifier: manifestStableIdentifier,
                report: report
            )
        }
        let candidatesArePortableAndDistinct = Set(candidateIDs).count == plausibleNodes.count
        let descriptionCounts = Dictionary(grouping: plausibleNodes, by: \.recordDescription)
            .mapValues(\.count)
        let candidates: [PublicIDRepairResolutionCandidate]
        if candidatesArePortableAndDistinct {
            candidates = zip(plausibleNodes, candidateIDs).map { node, candidateID in
                let description: String
                if descriptionCounts[node.recordDescription, default: 0] > 1 {
                    let snapshot = normalizedRecoveryCandidateSnapshot(
                        node: node,
                        manifestStableIdentifier: manifestStableIdentifier,
                        report: report
                    )
                    description = "\(node.recordDescription) — semantic fingerprint \(deterministicDigest(stableSnapshotKey(snapshot)).prefix(10))"
                } else {
                    description = node.recordDescription
                }
                return PublicIDRepairResolutionCandidate(
                    stableRecordIdentifier: candidateID,
                    recordDescription: description,
                    detail: "Current public ID: \(node.readPublicID().uuidString). Selecting this record binds the existing manifest identity to it; the authoritative manifest final ID is not regenerated.",
                    resultingPublicID: node.readPublicID()
                )
            }.sorted { $0.stableRecordIdentifier < $1.stableRecordIdentifier }
        } else {
            candidates = []
        }

        let reason: String
        if plausibleNodes.isEmpty {
            reason = "The record represented by \(backupAggregate.recordDescription) appears absent from the current local graph. The bound backup cannot restore a record that can no longer be identified, and local absence is not proof of intentional deletion. Recovery remains blocked until supported local/shared evidence can establish the record's identity or absence safely."
        } else if !candidatesArePortableAndDistinct {
            reason = "Multiple current records could represent \(backupAggregate.recordDescription), but they remain semantically indistinguishable after repair-owned values are normalized. Recovery remains blocked rather than using store-local identity to guess."
        } else if plausibleNodes.count == 1 {
            reason = "The bound backup no longer exactly matches \(backupAggregate.recordDescription), but one current semantic record is a plausible continuation. Confirm that binding before the existing manifest is replayed."
        } else {
            reason = "The bound backup no longer uniquely identifies \(backupAggregate.recordDescription). Choose the current semantic record that represents this existing manifest identity before repair continues."
        }

        return PublicIDRepairUnresolvedReference(
            kind: .indeterminateLocalRepairRecovery,
            entityType: backupAggregate.entityType,
            recordDescription: backupAggregate.recordDescription,
            stableRecordIdentifier: PublicIDRepairRecoverySelection.manualIssueStableIdentifier(
                for: manifestStableIdentifier
            ),
            fieldName: "manifestIdentityBinding",
            referencedPublicID: backupAggregate.publicID,
            reason: reason,
            candidates: candidates
        )
    }

    private func manualRecoveryCandidateIdentifier(
        node: AggregateNode,
        manifestStableIdentifier: String,
        report: PublicIDRepairReport
    ) -> String {
        let normalizedOwner = normalizedOriginalPublicID(
            node.herdPublicID,
            entityType: .herd,
            report: report
        )
        let snapshot = normalizedRecoveryCandidateSnapshot(
            node: node,
            manifestStableIdentifier: manifestStableIdentifier,
            report: report
        )
        return [
            "local-recovery-candidate-v1",
            node.entityType.rawValue,
            normalizedOwner?.uuidString.lowercased() ?? "nil",
            deterministicDigest(stableSnapshotKey(snapshot)),
        ].joined(separator: "|")
    }

    private func normalizedRecoveryCandidateSnapshot(
        node: AggregateNode,
        manifestStableIdentifier: String,
        report: PublicIDRepairReport
    ) -> CollaborationFieldSnapshot {
        var fields = CollaborationFieldSnapshotProvider.snapshot(for: node.aggregate)
        normalizeRepairOwnedFields(
            &fields,
            sourceStableIdentifier: manifestStableIdentifier,
            report: report
        )
        return fields
    }

    private func matchingNodes(
        for backup: BackupAggregate,
        stableRecordIdentifier: String,
        nodes: [AggregateNode],
        report: PublicIDRepairReport
    ) -> [AggregateNode] {
        let hasAuthoritativeRecordMapping = report.manifest.recordMappings.contains {
            $0.origin == .localSwiftData
                && $0.portableRecordIdentity == stableRecordIdentifier
        }
        return nodes.filter { node in
            guard node.entityType == backup.entityType else { return false }
            let normalizedOwner = normalizedOriginalPublicID(
                node.herdPublicID,
                entityType: .herd,
                report: report
            )
            let expectedOwner = normalizedOriginalPublicID(
                backup.herdPublicID,
                entityType: .herd,
                report: report
            )
            guard normalizedOwner == expectedOwner else { return false }

            if !hasAuthoritativeRecordMapping {
                let normalizedID = normalizedOriginalPublicID(
                    node.readPublicID(),
                    entityType: backup.entityType,
                    report: report
                )
                let expectedID = normalizedOriginalPublicID(
                    backup.publicID,
                    entityType: backup.entityType,
                    report: report
                )
                guard normalizedID == expectedID else { return false }
            }

            var fields = CollaborationFieldSnapshotProvider.snapshot(for: node.aggregate)
            normalizeRepairOwnedFields(
                &fields,
                sourceStableIdentifier: stableRecordIdentifier,
                report: report
            )
            var expectedFields = backup.sharedFields
            normalizeRepairOwnedFields(
                &expectedFields,
                sourceStableIdentifier: stableRecordIdentifier,
                report: report
            )
            return fields == expectedFields
        }
    }

    private func normalizedOriginalPublicID(
        _ value: UUID?,
        entityType: PublicIDRepairEntityType,
        report: PublicIDRepairReport
    ) -> UUID? {
        guard let value else { return nil }
        let candidates = report.manifest.recordMappings.filter {
            $0.origin == .localSwiftData
                && $0.entityType == entityType
                && $0.finalPublicID == value
        }
        let originals = Set(candidates.map(\.originalPublicID))
        return originals.count == 1 ? originals.first : value
    }

    private func normalizeRepairOwnedFields(
        _ fields: inout CollaborationFieldSnapshot,
        sourceStableIdentifier: String,
        report: PublicIDRepairReport
    ) {
        for transformation in report.manifest.referenceTransformations where
            transformation.origin == .localSwiftData
                && transformation.sourcePortableRecordIdentity == sourceStableIdentifier {
            // This field is itself one of the manifest-authorized mutations, so its current
            // value cannot decide which physical record the backup describes. Normalize both
            // current and backup snapshots to the immutable manifest's original reference.
            fields[transformation.fieldName] = transformation.previousPublicID.map {
                HerdSharingBridgeConflictValue(type: .uuid, encodedValue: $0.uuidString)
            } ?? .null
        }

        let replacementsByFinal = Dictionary(grouping: report.manifest.recordMappings.filter {
            $0.origin == .localSwiftData && $0.finalPublicID != $0.originalPublicID
        }, by: \.finalPublicID)
        for (fieldName, value) in fields where value.type == .uuid {
            guard let finalID = UUID(uuidString: value.encodedValue ?? ""),
                  let mappings = replacementsByFinal[finalID] else { continue }
            let originals = Set(mappings.map(\.originalPublicID))
            guard originals.count == 1, let original = originals.first else { continue }
            fields[fieldName] = HerdSharingBridgeConflictValue(
                type: .uuid,
                encodedValue: original.uuidString
            )
        }
    }

    private func treatmentItemRecoveryMatch(
        mapping: PublicIDRepairManifestRecordMapping,
        backup: PublicIDRepairBackup,
        locations: [TreatmentItemLocation],
        report: PublicIDRepairReport
    ) -> TreatmentItemRecoveryMatch? {
        guard mapping.entityType == .workingProtocolTemplate
                || mapping.entityType == .workingSession,
              let replacement = report.replacements.first(where: {
                  $0.stableRecordIdentifier == mapping.portableRecordIdentity
              }) else {
            return nil
        }
        let components = replacement.stableRecordIdentifier.split(separator: "|")
        guard components.count >= 7,
              let ownerOriginalID = UUID(uuidString: String(components[1])),
              let itemComponent = components.first(where: { $0.hasPrefix("item-") }),
              let itemIndex = Int(itemComponent.dropFirst("item-".count)) else {
            return nil
        }

        let locationMatches = locations.filter { location in
            location.entityType == mapping.entityType
                && location.itemIndex == itemIndex
                && normalizedOriginalPublicID(
                    location.ownerPublicID,
                    entityType: mapping.entityType,
                    report: report
                ) == ownerOriginalID
        }
        guard locationMatches.count == 1, let location = locationMatches.first else {
            return nil
        }

        var normalizedLocationItem = location.item
        normalizedLocationItem.id = mapping.originalPublicID
        let locationKey = stableTreatmentItemKey(normalizedLocationItem)
        let candidateBackups = backup.treatmentItems.filter { candidate in
            guard candidate.entityType == mapping.entityType,
                  candidate.itemIndex == itemIndex,
                  candidate.item.id == mapping.originalPublicID
                    || candidate.item.id == mapping.finalPublicID else {
                return false
            }
            var normalizedBackupItem = candidate.item
            normalizedBackupItem.id = mapping.originalPublicID
            return stableTreatmentItemKey(normalizedBackupItem) == locationKey
        }
        guard candidateBackups.count == 1, let backupItem = candidateBackups.first else {
            return nil
        }
        return TreatmentItemRecoveryMatch(location: location, backupItem: backupItem)
    }

    private func treatmentItemRecoveryMutation(
        mapping: PublicIDRepairManifestRecordMapping,
        backup: PublicIDRepairBackup,
        locations: [TreatmentItemLocation],
        report: PublicIDRepairReport
    ) -> RecoveryMutation? {
        guard let match = treatmentItemRecoveryMatch(
            mapping: mapping,
            backup: backup,
            locations: locations,
            report: report
        ) else {
            return nil
        }

        let current = match.location.readPublicID()
        let baseline = match.backupItem.item.id
        let state: PublicIDRepairRecoveryTransformationState
        let evidenceKind: PublicIDRepairRecoveryEvidenceKind
        if current == mapping.finalPublicID {
            state = .alreadyApplied
            evidenceKind = .matchedSafelyToBackup
        } else if baseline != mapping.finalPublicID && current == baseline {
            state = .definitelyNotApplied
            evidenceKind = .matchedSafelyToBackup
        } else {
            state = .contradictoryOrAmbiguous
            evidenceKind = .repairOwnedValueChangedOnIdentifiableRecord
        }
        let description = "Treatment item \(mapping.recordDescription) is uniquely identifiable against the bound backup."
        return RecoveryMutation(
            state: state,
            canRestoreFromBackup: true,
            applyFinal: { match.location.assignPublicID(mapping.finalPublicID) },
            applyBackup: { match.location.assignPublicID(baseline) },
            description: description,
            evidence: PublicIDRepairRecoveryEvidence(
                stableRecordIdentifier: mapping.portableRecordIdentity,
                kind: evidenceKind,
                description: description
            )
        )
    }

    /// The outer optional distinguishes an unsupported field from a supported optional UUID whose
    /// current value is nil. A nil reference is a valid generation-backup state and recoverable.
    private func readRepairReference(
        fieldName: String,
        aggregate: any CollaborativelyMutableAggregate
    ) -> UUID?? {
        switch (aggregate, fieldName) {
        case (let animal as Animal, "tagColorID"): .some(animal.tagColorID)
        case (let animal as Animal, "statusReferenceID"): .some(animal.statusReferenceID)
        case (let tag as AnimalTag, "colorID"): .some(tag.colorID)
        case (let record as StatusRecord, "oldStatusReferenceID"): .some(record.oldStatusReferenceID)
        case (let record as StatusRecord, "newStatusReferenceID"): .some(record.newStatusReferenceID)
        case (let session as FieldCheckSession, "pastureID"): .some(session.pastureID)
        case (let check as FieldCheckAnimalCheck, "animalIDSnapshot"): .some(check.animalIDSnapshot)
        case (let check as FieldCheckAnimalCheck, "rosterTagColorID"): .some(check.rosterTagColorID)
        case (let check as FieldCheckAnimalCheck, "damRosterTagColorID"): .some(check.damRosterTagColorID)
        case (let finding as FieldCheckFinding, "animalIDSnapshot"): .some(finding.animalIDSnapshot)
        case (let finding as FieldCheckFinding, "sessionIDSnapshot"): .some(finding.sessionIDSnapshot)
        case (let finding as FieldCheckFinding, "animalDisplayTagColorIDSnapshot"): .some(finding.animalDisplayTagColorIDSnapshot)
        case (let treatment as WorkingTreatmentRecord, "treatmentItemID"): .some(treatment.treatmentItemID)
        default: nil
        }
    }

    private func backupRepairReference(
        fieldName: String,
        aggregate: BackupAggregate
    ) -> UUID?? {
        guard let value = aggregate.sharedFields[fieldName] else { return nil }
        switch value.type {
        case .null:
            return .some(nil)
        case .uuid, .string:
            guard let encoded = value.encodedValue,
                  let uuid = UUID(uuidString: encoded) else {
                return nil
            }
            return .some(uuid)
        case .bool, .int, .double, .date:
            return nil
        }
    }

    private func assignRepairReference(
        _ value: UUID?,
        fieldName: String,
        aggregate: any CollaborativelyMutableAggregate
    ) {
        switch (aggregate, fieldName) {
        case (let animal as Animal, "tagColorID"): animal.tagColorID = value
        case (let animal as Animal, "statusReferenceID"): animal.statusReferenceID = value
        case (let tag as AnimalTag, "colorID"): tag.colorID = value
        case (let record as StatusRecord, "oldStatusReferenceID"): record.oldStatusReferenceID = value
        case (let record as StatusRecord, "newStatusReferenceID"): record.newStatusReferenceID = value
        case (let session as FieldCheckSession, "pastureID"): session.pastureID = value
        case (let check as FieldCheckAnimalCheck, "animalIDSnapshot"): check.animalIDSnapshot = value
        case (let check as FieldCheckAnimalCheck, "rosterTagColorID"): check.rosterTagColorID = value
        case (let check as FieldCheckAnimalCheck, "damRosterTagColorID"): check.damRosterTagColorID = value
        case (let finding as FieldCheckFinding, "animalIDSnapshot"): finding.animalIDSnapshot = value
        case (let finding as FieldCheckFinding, "sessionIDSnapshot"): finding.sessionIDSnapshot = value
        case (let finding as FieldCheckFinding, "animalDisplayTagColorIDSnapshot"): finding.animalDisplayTagColorIDSnapshot = value
        case (let treatment as WorkingTreatmentRecord, "treatmentItemID"):
            if let value { treatment.treatmentItemID = value }
        default: break
        }
    }

    private func loadBoundBackup(
        for report: PublicIDRepairReport
    ) throws -> PublicIDRepairBackup {
        let backupGenerations = report.manifest.generations.filter { $0.backup != nil }
        guard let journalGeneration = backupGenerations.last,
              let journalBackup = journalGeneration.backup,
              journalBackup.path == report.backupPath,
              journalBackup.filename == report.backupFilename else {
            throw PublicIDRepairRecoveryError.backupTransactionMismatch
        }

        // Always validate the backup named by the pending journal. For a restore generation this
        // is the pre-restore damaged-state safety copy. It is durable evidence for this same
        // transaction, but it must never become the source baseline for replay after a crash.
        _ = try decodeValidatedBackup(journalBackup, report: report)

        let restoreMarker = "local-recovery|\(PublicIDRepairRecoveryChoice.restorePreRepairBackup.rawValue)"
        let sourceGeneration: PublicIDRepairManifestGeneration
        if journalGeneration.selectedResolutionIDs.contains(restoreMarker) {
            guard let prior = backupGenerations.dropLast().reversed().first(where: {
                !$0.selectedResolutionIDs.contains(restoreMarker)
            }) else {
                throw PublicIDRepairRecoveryError.backupTransactionMismatch
            }
            sourceGeneration = prior
        } else {
            sourceGeneration = journalGeneration
        }

        guard let sourceBackup = sourceGeneration.backup else {
            throw PublicIDRepairRecoveryError.backupTransactionMismatch
        }
        return try decodeValidatedBackup(sourceBackup, report: report)
    }

    private func decodeValidatedBackup(
        _ reference: PublicIDRepairBackupReference,
        report: PublicIDRepairReport
    ) throws -> PublicIDRepairBackup {
        guard FileManager.default.fileExists(atPath: reference.path) else {
            throw PublicIDRepairRecoveryError.backupUnavailable
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: reference.path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(PublicIDRepairBackup.self, from: data)
        guard backup.formatVersion == 4 else {
            throw PublicIDRepairRecoveryError.backupFormatUnsupported(backup.formatVersion)
        }

        let localMappingIDs = Set(report.manifest.recordMappings.filter {
            $0.origin == .localSwiftData && !$0.retainedOriginalID
        }.map { mapping in
            "\(mapping.entityType.rawValue)|\(mapping.portableRecordIdentity)|\(mapping.finalPublicID.uuidString)"
        })
        let backupMappingIDs = Set(backup.replacements.map(\.id))
        guard localMappingIDs == backupMappingIDs else {
            throw PublicIDRepairRecoveryError.backupTransactionMismatch
        }

        let localReferenceIDs = Set(report.manifest.referenceTransformations.filter {
            $0.origin == .localSwiftData && $0.sourceEntityType != nil
        }.map { transformation in
            "\(transformation.sourceEntityType!.rawValue)|\(transformation.sourcePortableRecordIdentity)|\(transformation.fieldName)"
        })
        let backupReferenceIDs = Set(backup.referenceUpdates.map(\.id))
        guard localReferenceIDs == backupReferenceIDs else {
            throw PublicIDRepairRecoveryError.backupTransactionMismatch
        }
        return backup
    }

    private func createRecoveryBoundaryBackup(
        loaded: LoadedRecords,
        sourceBackup: PublicIDRepairBackup,
        report: PublicIDRepairReport
    ) throws -> URL {
        let nodes = makeAggregateNodes(loaded: loaded)
        let graph = relationshipFingerprints(loaded: loaded, nodes: nodes)
        let persistedBindings = PublicIDRepairRecoverySelection.manualBindings(
            in: report.manifest
        )
        var stableIDByLocalID: [String: String] = [:]
        let aggregates = nodes.map { node -> BackupAggregate in
            let strictMatches = sourceBackup.aggregates.filter { source in
                matchingNodes(
                    for: source,
                    stableRecordIdentifier: source.stableRecordIdentifier,
                    nodes: [node],
                    report: report
                ).count == 1
            }
            let manuallyBoundMatches = sourceBackup.aggregates.filter { source in
                let issue = manualRecoveryIssue(
                    backupAggregate: source,
                    manifestStableIdentifier: source.stableRecordIdentifier,
                    plausibleNodes: [node],
                    report: report
                )
                guard let selectedCandidateID = persistedBindings[issue.id] else {
                    return false
                }
                return manualRecoveryCandidateIdentifier(
                    node: node,
                    manifestStableIdentifier: source.stableRecordIdentifier,
                    report: report
                ) == selectedCandidateID
            }
            let source: BackupAggregate?
            if strictMatches.count == 1 {
                source = strictMatches.first
            } else if manuallyBoundMatches.count == 1 {
                source = manuallyBoundMatches.first
            } else {
                source = nil
            }
            let snapshot = CollaborationFieldSnapshotProvider.snapshot(for: node.aggregate)
            let stableID = source?.stableRecordIdentifier ?? [
                "recovery-boundary",
                node.entityType.rawValue,
                node.readPublicID().uuidString.lowercased(),
                deterministicDigest(stableSnapshotKey(snapshot)),
                graph[node.localIdentifier] ?? "",
            ].joined(separator: "|")
            stableIDByLocalID[node.localIdentifier] = stableID
            return BackupAggregate(
                entityType: node.entityType,
                stableRecordIdentifier: stableID,
                recordDescription: node.recordDescription,
                publicID: node.readPublicID(),
                herdPublicID: node.herdPublicID,
                sharedFields: snapshot
            )
        }.sorted {
            if $0.entityType != $1.entityType {
                return $0.entityType.rawValue < $1.entityType.rawValue
            }
            return $0.stableRecordIdentifier < $1.stableRecordIdentifier
        }
        let treatmentItems = makeTreatmentItemLocations(loaded: loaded).map { location in
            BackupTreatmentItem(
                entityType: location.entityType,
                ownerStableRecordIdentifier: stableIDByLocalID[location.ownerLocalIdentifier]
                    ?? "recovery-owner|\(location.ownerPublicID.uuidString.lowercased())",
                itemIndex: location.itemIndex,
                item: location.item
            )
        }.sorted {
            if $0.entityType != $1.entityType {
                return $0.entityType.rawValue < $1.entityType.rawValue
            }
            if $0.ownerStableRecordIdentifier != $1.ownerStableRecordIdentifier {
                return $0.ownerStableRecordIdentifier < $1.ownerStableRecordIdentifier
            }
            return $0.itemIndex < $1.itemIndex
        }
        let backup = PublicIDRepairBackup(
            formatVersion: 4,
            createdAt: .now,
            assessment: report.assessment,
            replacements: report.replacements.filter { replacement in
                report.manifest.recordMappings.contains {
                    $0.origin == .localSwiftData
                        && !$0.retainedOriginalID
                        && $0.portableRecordIdentity == replacement.stableRecordIdentifier
                }
            },
            referenceUpdates: report.referenceUpdates.filter { update in
                report.manifest.referenceTransformations.contains {
                    $0.origin == .localSwiftData
                        && $0.sourcePortableRecordIdentity == update.stableRecordIdentifier
                        && $0.fieldName == update.fieldName
                }
            },
            resolutions: [],
            aggregates: aggregates,
            treatmentItems: treatmentItems,
            revisionRecords: loaded.revisionRecords.map(makeBackupRevisionRecord)
                .sorted { $0.stableRecordIdentifier < $1.stableRecordIdentifier }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        let directoryURL = try backupDirectoryURL()
        let filename = "yaHerd-PublicID-Repair-Recovery-\(backupTimestamp())-\(UUID().uuidString.lowercased()).json"
        let url = directoryURL.appendingPathComponent(filename, isDirectory: false)
        try PublicIDRepairDurableFile.persist(data, to: url)
        return url
    }

    private func restoreRepairBoundary(
        plan: RecoveryPlan,
        report: PublicIDRepairReport,
        didCommit: PublicIDRepairDidCommit
    ) async throws {
        let assessment = plan.assessment
        guard assessment.requiresBackupRestore else {
            throw PublicIDRepairRecoveryError.invalidChoice
        }

        // Restore only repair-owned fields to the exact source values stored by the backup bound
        // to this manifest generation. Already-final fields whose baseline was already final stay
        // final; unrelated shared fields were used for unique matching and are never overwritten.
        for mutation in plan.mutations where mutation.canRestoreFromBackup {
            mutation.applyBackup()
        }

        try restoreRevisionBoundary(from: plan.backup, report: report)
        try PersistenceLog.save(
            modelContext,
            operation: "DeterministicSwiftDataPublicIDRepairService.restoreRepairBoundary"
        )
        await didCommit()
    }

    private func restoreRevisionBoundary(
        from backup: PublicIDRepairBackup,
        report: PublicIDRepairReport
    ) throws {
        let aggregateMappings = report.manifest.recordMappings.filter {
            $0.origin == .localSwiftData && !isTreatmentItemManifestMapping($0)
        }
        let affectedTypesAndIDs: Set<String> = Set(
            aggregateMappings.flatMap { mapping in
                [
                    "\(collaborationSourceName(for: mapping.entityType))|\(mapping.originalPublicID.uuidString.lowercased())",
                    "\(collaborationSourceName(for: mapping.entityType))|\(mapping.finalPublicID.uuidString.lowercased())",
                ]
            }
        )
        let affectedSourceStableIDs = Set(
            report.manifest.referenceTransformations.filter {
                $0.origin == .localSwiftData
            }.map(\.sourcePortableRecordIdentity)
        )
        let affectedBackupAggregates = backup.aggregates.filter {
            affectedSourceStableIDs.contains($0.stableRecordIdentifier)
                || affectedTypesAndIDs.contains(
                    "\(collaborationSourceName(for: $0.entityType))|\($0.publicID.uuidString.lowercased())"
                )
        }
        let affectedKeys = Set(affectedBackupAggregates.map {
            "\(collaborationSourceName(for: $0.entityType))|\($0.publicID.uuidString.lowercased())"
        })

        let current = try fetchAll(CollaborationRevisionRecord.self)
        for record in current {
            let key = "\(record.sourceEntityName)|\(record.aggregatePublicID.uuidString.lowercased())"
            if affectedKeys.contains(key) || affectedTypesAndIDs.contains(key) {
                modelContext.delete(record)
            }
        }
        for saved in backup.revisionRecords {
            let key = "\(saved.sourceEntityName)|\(saved.aggregatePublicID.uuidString.lowercased())"
            guard affectedKeys.contains(key) else { continue }
            let metadata = CollaborationRevisionMetadata(
                modifiedAt: saved.modifiedAt,
                revision: saved.revision,
                modifiedByParticipantID: saved.modifiedByParticipantID,
                modifiedByDeviceID: saved.modifiedByDeviceID,
                baseRevision: saved.baseRevision,
                baseFieldValues: CollaborationRevisionMetadata.decodeFieldSnapshot(saved.baseFieldValuesData),
                currentFieldValues: CollaborationRevisionMetadata.decodeFieldSnapshot(saved.currentFieldValuesData),
                isDeleted: saved.isDeleted
            )
            let restored = CollaborationRevisionRecord(
                publicID: saved.publicID,
                key: CollaborationAggregateKey(
                    sourceEntityName: saved.sourceEntityName,
                    publicID: saved.aggregatePublicID
                ),
                herdPublicID: saved.herdPublicID,
                metadata: metadata
            )
            // The initializer canonicalizes revision snapshots. Recovery must restore the exact
            // durable boundary, including legacy/noncanonical encoded revision payloads.
            restored.aggregateKey = saved.aggregateKey
            restored.sourceEntityName = saved.sourceEntityName
            restored.aggregatePublicID = saved.aggregatePublicID
            restored.herdPublicID = saved.herdPublicID
            restored.modifiedAt = saved.modifiedAt
            restored.revision = saved.revision
            restored.modifiedByParticipantID = saved.modifiedByParticipantID
            restored.modifiedByDeviceID = saved.modifiedByDeviceID
            restored.baseRevision = saved.baseRevision
            restored.baseFieldValuesData = saved.baseFieldValuesData
            restored.currentFieldValuesData = saved.currentFieldValuesData
            restored.isDeleted = saved.isDeleted
            modelContext.insert(restored)
        }
    }

    private func isTreatmentItemManifestMapping(
        _ mapping: PublicIDRepairManifestRecordMapping
    ) -> Bool {
        (mapping.entityType == .workingProtocolTemplate || mapping.entityType == .workingSession)
            && mapping.portableRecordIdentity.split(separator: "|").contains {
                $0.hasPrefix("item-")
            }
    }

    private func verifyBackupBoundary(
        report: PublicIDRepairReport
    ) throws {
        let backup = try loadBoundBackup(for: report)
        let loaded = try loadRecords()
        let nodes = makeAggregateNodes(loaded: loaded)
        let treatmentLocations = makeTreatmentItemLocations(loaded: loaded)
        let aggregateStableIDs = Set(
            report.manifest.recordMappings.filter {
                $0.origin == .localSwiftData && !isTreatmentItemManifestMapping($0)
            }.map(\.portableRecordIdentity)
            + report.manifest.referenceTransformations.filter {
                $0.origin == .localSwiftData && $0.sourceEntityType != nil
            }.map(\.sourcePortableRecordIdentity)
        )

        for stableID in aggregateStableIDs.sorted() {
            guard let backupAggregate = backup.aggregates.first(where: {
                $0.stableRecordIdentifier == stableID
            }) else {
                throw PublicIDRepairRecoveryError.restorationVerificationFailed(
                    "The bound backup does not contain affected aggregate \(stableID)."
                )
            }
            let matches = matchingNodes(
                for: backupAggregate,
                stableRecordIdentifier: stableID,
                nodes: nodes,
                report: report
            )
            guard matches.count == 1, let node = matches.first else {
                throw PublicIDRepairRecoveryError.restorationVerificationFailed(
                    "Affected aggregate \(backupAggregate.recordDescription) is not uniquely identifiable after restoration."
                )
            }
            guard node.readPublicID() == backupAggregate.publicID,
                  node.herdPublicID == backupAggregate.herdPublicID,
                  CollaborationFieldSnapshotProvider.snapshot(for: node.aggregate)
                    == backupAggregate.sharedFields else {
                throw PublicIDRepairRecoveryError.restorationVerificationFailed(
                    "Affected aggregate \(backupAggregate.recordDescription) does not exactly match the bound generation backup."
                )
            }
        }

        for mapping in report.manifest.recordMappings where
            mapping.origin == .localSwiftData
                && isTreatmentItemManifestMapping(mapping)
                && !mapping.retainedOriginalID {
            guard let match = treatmentItemRecoveryMatch(
                mapping: mapping,
                backup: backup,
                locations: treatmentLocations,
                report: report
            ), match.location.readPublicID() == match.backupItem.item.id else {
                throw PublicIDRepairRecoveryError.restorationVerificationFailed(
                    "Treatment-item state for \(mapping.recordDescription) does not exactly match the bound generation backup."
                )
            }
        }

        try verifyRestoredRevisionBoundary(
            from: backup,
            report: report
        )
    }

    private func verifyRestoredRevisionBoundary(
        from backup: PublicIDRepairBackup,
        report: PublicIDRepairReport
    ) throws {
        let aggregateMappings = report.manifest.recordMappings.filter {
            $0.origin == .localSwiftData && !isTreatmentItemManifestMapping($0)
        }
        let affectedTypesAndIDs: Set<String> = Set(
            aggregateMappings.flatMap { mapping in
                [
                    "\(collaborationSourceName(for: mapping.entityType))|\(mapping.originalPublicID.uuidString.lowercased())",
                    "\(collaborationSourceName(for: mapping.entityType))|\(mapping.finalPublicID.uuidString.lowercased())",
                ]
            }
        )
        let affectedSourceStableIDs = Set(
            report.manifest.referenceTransformations.filter {
                $0.origin == .localSwiftData
            }.map(\.sourcePortableRecordIdentity)
        )
        let affectedBackupAggregates = backup.aggregates.filter {
            affectedSourceStableIDs.contains($0.stableRecordIdentifier)
                || affectedTypesAndIDs.contains(
                    "\(collaborationSourceName(for: $0.entityType))|\($0.publicID.uuidString.lowercased())"
                )
        }
        let affectedKeys = Set(affectedBackupAggregates.map {
            "\(collaborationSourceName(for: $0.entityType))|\($0.publicID.uuidString.lowercased())"
        })
        let expected = backup.revisionRecords.filter { saved in
            affectedKeys.contains(
                "\(saved.sourceEntityName)|\(saved.aggregatePublicID.uuidString.lowercased())"
            )
        }.map(revisionBoundarySignature).sorted()
        let current = try fetchAll(CollaborationRevisionRecord.self).filter { record in
            affectedKeys.contains(
                "\(record.sourceEntityName)|\(record.aggregatePublicID.uuidString.lowercased())"
            )
        }.map(makeBackupRevisionRecord).map(revisionBoundarySignature).sorted()

        guard current == expected else {
            throw PublicIDRepairRecoveryError.restorationVerificationFailed(
                "Revision metadata for the restored repair boundary does not match the bound backup."
            )
        }
    }

    private func revisionBoundarySignature(_ record: BackupRevisionRecord) -> String {
        [
            record.stableRecordIdentifier,
            record.publicID.uuidString.lowercased(),
            record.aggregateKey,
            record.sourceEntityName,
            record.aggregatePublicID.uuidString.lowercased(),
            record.herdPublicID?.uuidString.lowercased() ?? "nil",
            String(record.modifiedAt.timeIntervalSinceReferenceDate),
            String(record.revision),
            record.modifiedByParticipantID,
            record.modifiedByDeviceID,
            String(record.baseRevision),
            record.baseFieldValuesData?.base64EncodedString() ?? "nil",
            record.currentFieldValuesData?.base64EncodedString() ?? "nil",
            record.isDeleted ? "deleted" : "live",
        ].joined(separator: "|")
    }

    private func verifyManifestBoundary(
        _ report: PublicIDRepairReport
    ) throws {
        let replayPlan = try makeRecoveryPlan(for: report)
        let invalid = replayPlan.mutations.filter { $0.state != .alreadyApplied }
        guard invalid.isEmpty else {
            throw PublicIDRepairRecoveryError.restorationVerificationFailed(
                invalid.first?.description ?? "A manifest transformation is not applied."
            )
        }
    }

    private func reportWithManifest(
        _ source: PublicIDRepairReport,
        manifest: PublicIDRepairManifest,
        backup: PublicIDRepairBackupReference
    ) -> PublicIDRepairReport {
        let priorBackups = manifest.backupReferences.filter { $0.path != backup.path }
        return PublicIDRepairReport(
            completedAt: .now,
            assessment: source.assessment,
            replacements: [],
            referenceUpdates: [],
            backupFilename: backup.filename,
            backupPath: backup.path,
            validationIssueCount: source.validationIssueCount,
            priorBackups: priorBackups.isEmpty ? nil : priorBackups,
            manifest: manifest
        )
    }

    private func replacingLatestValidation(
        in manifest: PublicIDRepairManifest,
        with value: Bool
    ) -> PublicIDRepairManifest {
        guard let latest = manifest.generations.last else { return manifest }
        let replacement = PublicIDRepairManifestGeneration(
            number: latest.number,
            capturedAt: latest.capturedAt,
            backup: latest.backup,
            recordMappings: latest.recordMappings,
            referenceTransformations: latest.referenceTransformations,
            selectedResolutionIDs: latest.selectedResolutionIDs,
            bridgeRecoveryActions: latest.bridgeRecoveryActions,
            validationPassed: value
        )
        return PublicIDRepairManifest(
            schemaVersion: manifest.schemaVersion,
            generations: Array(manifest.generations.dropLast()) + [replacement]
        )
    }

    private func collaborationSourceName(
        for entityType: PublicIDRepairEntityType
    ) -> String {
        switch entityType {
        case .herd: CollaborationAggregateType.herd.rawValue
        case .tagColorDefinition: CollaborationAggregateType.tagColorDefinition.rawValue
        case .animalStatusReference: CollaborationAggregateType.animalStatusReference.rawValue
        case .pastureGroup: CollaborationAggregateType.pastureGroup.rawValue
        case .pasture: CollaborationAggregateType.pasture.rawValue
        case .animal: CollaborationAggregateType.animal.rawValue
        case .animalTag: CollaborationAggregateType.animalTag.rawValue
        case .movement: CollaborationAggregateType.movement.rawValue
        case .statusRecord: CollaborationAggregateType.statusRecord.rawValue
        case .workingProtocolTemplate: CollaborationAggregateType.workingProtocolTemplate.rawValue
        case .workingSession: CollaborationAggregateType.workingSession.rawValue
        case .workingQueueItem: CollaborationAggregateType.workingQueueItem.rawValue
        case .workingTreatmentRecord: CollaborationAggregateType.workingTreatmentRecord.rawValue
        case .healthRecord: CollaborationAggregateType.healthRecord.rawValue
        case .pregnancyCheck: CollaborationAggregateType.pregnancyCheck.rawValue
        case .fieldCheckSession: CollaborationAggregateType.fieldCheckSession.rawValue
        case .fieldCheckAnimalCheck: CollaborationAggregateType.fieldCheckAnimalCheck.rawValue
        case .fieldCheckFinding: CollaborationAggregateType.fieldCheckFinding.rawValue
        }
    }
}
