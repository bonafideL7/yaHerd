import Foundation
import SwiftData

extension DeterministicSwiftDataPublicIDRepairService {
    func makeTreatmentItemLocations(loaded: LoadedRecords) -> [TreatmentItemLocation] {
        var locations: [TreatmentItemLocation] = []
        for template in loaded.workingProtocolTemplates {
            let ownerSnapshotKey = stableSnapshotKey(
                CollaborationFieldSnapshotProvider.snapshot(for: template)
            )
            for index in template.items.indices {
                let original = template.items[index]
                locations.append(
                    TreatmentItemLocation(
                        entityType: .workingProtocolTemplate,
                        ownerLocalIdentifier: localRecordIdentifier(template),
                        ownerPublicID: template.publicID,
                        ownerSnapshotKey: ownerSnapshotKey,
                        itemIndex: index,
                        localIdentifier: localTreatmentItemIdentifier(owner: template, index: index),
                        originalID: original.id,
                        item: original,
                        ownerDescription: template.name.isEmpty ? "Unnamed working protocol" : template.name,
                        session: nil,
                        readPublicID: {
                            guard template.items.indices.contains(index) else { return original.id }
                            return template.items[index].id
                        },
                        assignPublicID: { replacementID in
                            guard template.items.indices.contains(index) else { return }
                            var items = template.items
                            items[index].id = replacementID
                            template.items = items
                        }
                    )
                )
            }
        }
        for session in loaded.workingSessions {
            let ownerSnapshotKey = stableSnapshotKey(
                CollaborationFieldSnapshotProvider.snapshot(for: session)
            )
            for index in session.protocolItems.indices {
                let original = session.protocolItems[index]
                locations.append(
                    TreatmentItemLocation(
                        entityType: .workingSession,
                        ownerLocalIdentifier: localRecordIdentifier(session),
                        ownerPublicID: session.publicID,
                        ownerSnapshotKey: ownerSnapshotKey,
                        itemIndex: index,
                        localIdentifier: localTreatmentItemIdentifier(owner: session, index: index),
                        originalID: original.id,
                        item: original,
                        ownerDescription: "Working session on \(session.date.formatted(date: .abbreviated, time: .omitted))",
                        session: session,
                        readPublicID: {
                            guard session.protocolItems.indices.contains(index) else { return original.id }
                            return session.protocolItems[index].id
                        },
                        assignPublicID: { replacementID in
                            guard session.protocolItems.indices.contains(index) else { return }
                            var items = session.protocolItems
                            items[index].id = replacementID
                            session.protocolItems = items
                        }
                    )
                )
            }
        }
        return locations
    }

    func makeTreatmentItemPlan(
        locations: [TreatmentItemLocation],
        entityType: PublicIDRepairEntityType,
        graphFingerprintByLocalIdentifier: [String: String]
    ) -> EntityPlan {
        let groupsByOwner = Dictionary(grouping: locations, by: \.ownerLocalIdentifier)
        var duplicateGroupCount = 0
        var replacements: [PlannedReplacement] = []
        var candidates: [DuplicateCandidate] = []

        for ownerLocations in groupsByOwner.values {
            let groups = Dictionary(grouping: ownerLocations, by: \.originalID)
                .filter { $0.value.count > 1 }
                .sorted { $0.key.uuidString < $1.key.uuidString }
            duplicateGroupCount += groups.count
            var usedIDs = Set(ownerLocations.map(\.originalID))

            for (retainedID, duplicateLocations) in groups {
                let ordered = duplicateLocations.sorted { lhs, rhs in
                    treatmentItemSortKey(
                        lhs,
                        graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier
                    ) < treatmentItemSortKey(
                        rhs,
                        graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier
                    )
                }
                for (ordinal, location) in ordered.enumerated() {
                    let stableIdentifier = treatmentItemCandidateIdentifier(
                        location,
                        entityType: entityType,
                        graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
                        suffix: "candidate-\(ordinal)"
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
                                    recordDescription: "\(location.item.name.isEmpty ? "Unnamed treatment item" : location.item.name) in \(location.ownerDescription)",
                                    stableRecordIdentifier: stableIdentifier,
                                    retainedPublicID: retainedID,
                                    replacementPublicID: resultingID
                                ),
                                localRecordIdentifier: location.localIdentifier,
                                readPublicID: location.readPublicID,
                                assignPublicID: location.assignPublicID
                            )
                        )
                    }
                    candidates.append(
                        DuplicateCandidate(
                            entityType: entityType,
                            localIdentifier: location.localIdentifier,
                            stableRecordIdentifier: stableIdentifier,
                            recordDescription: location.item.name.isEmpty ? "Unnamed treatment item" : location.item.name,
                            detail: treatmentCandidateDetail(
                                location.item,
                                retainsOriginalID: ordinal == 0
                            ),
                            retainedPublicID: retainedID,
                            resultingPublicID: resultingID
                        )
                    )
                }
            }

            // Stale treatment references can point to an ID that is no longer present in the
            // session. Keep every current item addressable as a portable manual-repair
            // candidate, even when that item's own ID is already unique.
            let plannedLocalIdentifiers = Set(candidates.map(\.localIdentifier))
            for location in ownerLocations where !plannedLocalIdentifiers.contains(location.localIdentifier) {
                candidates.append(
                    DuplicateCandidate(
                        entityType: entityType,
                        localIdentifier: location.localIdentifier,
                        stableRecordIdentifier: treatmentItemCandidateIdentifier(
                            location,
                            entityType: entityType,
                            graphFingerprintByLocalIdentifier: graphFingerprintByLocalIdentifier,
                            suffix: "candidate-current"
                        ),
                        recordDescription: location.item.name.isEmpty ? "Unnamed treatment item" : location.item.name,
                        detail: treatmentCandidateDetail(
                            location.item,
                            retainsOriginalID: true
                        ),
                        retainedPublicID: location.originalID,
                        resultingPublicID: location.originalID
                    )
                )
            }
        }

        return EntityPlan(
            assessment: PublicIDRepairEntityAssessment(
                entityType: entityType,
                scannedRecordCount: 0,
                duplicateGroupCount: duplicateGroupCount,
                duplicateRecordCount: replacements.count
            ),
            replacements: replacements,
            candidates: candidates,
            unresolvedIssues: []
        )
    }

    func mergeTreatmentItemPlan(
        _ itemPlan: EntityPlan,
        into plans: inout [EntityPlan],
        entityType: PublicIDRepairEntityType
    ) {
        guard let index = plans.firstIndex(where: { $0.assessment.entityType == entityType }) else {
            return
        }
        let base = plans[index]
        plans[index] = EntityPlan(
            assessment: PublicIDRepairEntityAssessment(
                entityType: entityType,
                scannedRecordCount: base.assessment.scannedRecordCount,
                duplicateGroupCount: base.assessment.duplicateGroupCount
                    + itemPlan.assessment.duplicateGroupCount,
                duplicateRecordCount: base.assessment.duplicateRecordCount
                    + itemPlan.assessment.duplicateRecordCount
            ),
            replacements: base.replacements + itemPlan.replacements,
            candidates: base.candidates + itemPlan.candidates,
            unresolvedIssues: base.unresolvedIssues + itemPlan.unresolvedIssues
        )
    }

    func treatmentItemSortKey(
        _ location: TreatmentItemLocation,
        graphFingerprintByLocalIdentifier: [String: String]
    ) -> String {
        [
            deterministicDigest(stableTreatmentItemKey(location.item)),
            graphFingerprintByLocalIdentifier[location.ownerLocalIdentifier] ?? "",
            String(format: "%08d", location.itemIndex),
        ].joined(separator: "|")
    }

    func treatmentItemCandidateIdentifier(
        _ location: TreatmentItemLocation,
        entityType: PublicIDRepairEntityType,
        graphFingerprintByLocalIdentifier: [String: String],
        suffix: String
    ) -> String {
        let ownerGraph = graphFingerprintByLocalIdentifier[location.ownerLocalIdentifier] ?? ""
        return [
            entityType.rawValue,
            location.ownerPublicID.uuidString.lowercased(),
            deterministicDigest(location.ownerSnapshotKey),
            ownerGraph,
            location.originalID.uuidString.lowercased(),
            deterministicDigest(stableTreatmentItemKey(location.item)),
            "item-\(location.itemIndex)",
            suffix,
        ].joined(separator: "|")
    }

    func stableTreatmentItemKey(_ item: WorkingProtocolItem) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(item) else {
            return "\(normalizedTreatmentName(item.name))|\(item.id.uuidString.lowercased())"
        }
        return String(data: data, encoding: .utf8)
            ?? "\(normalizedTreatmentName(item.name))|\(item.id.uuidString.lowercased())"
    }

    func treatmentCandidateDetail(
        _ item: WorkingProtocolItem,
        retainsOriginalID: Bool
    ) -> String {
        let role = retainsOriginalID ? "Keeps the existing public ID" : "Receives a replacement public ID"
        let dose = item.suggestedDose.formattedDescription
        return dose.isEmpty ? role : "\(role). Suggested dose: \(dose)."
    }

    func animalDescription(_ animal: Animal?) -> String {
        guard let animal else { return "unknown animal" }
        let tag = animal.tagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty { return "animal \(tag)" }
        let name = animal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "untagged animal" : name
    }
}
