import Foundation

extension DeterministicSwiftDataPublicIDRepairService {
    /// Human-readable relationship context for diagnostics. The deterministic graph fingerprint
    /// remains the canonical sort input, but users should never have to infer a choice from hashes.
    func relationshipContexts(
        loaded: LoadedRecords,
        nodes: [AggregateNode]
    ) -> [String: String] {
        let nodeByObject = Dictionary(uniqueKeysWithValues: nodes.map {
            (ObjectIdentifier($0.aggregate), $0)
        })
        var descriptors: [String: [String]] = [:]

        func addEdge(
            _ source: (any CollaborativelyMutableAggregate)?,
            _ target: (any CollaborativelyMutableAggregate)?,
            _ label: String
        ) {
            guard let source, let target,
                  let sourceNode = nodeByObject[ObjectIdentifier(source)],
                  let targetNode = nodeByObject[ObjectIdentifier(target)] else {
                return
            }
            descriptors[sourceNode.localIdentifier, default: []].append(
                "\(humanizedRepairLabel(label)): \(targetNode.recordDescription)"
            )
            descriptors[targetNode.localIdentifier, default: []].append(
                "Related \(sourceNode.entityType.displayName.lowercased()): \(sourceNode.recordDescription)"
            )
        }

        for record in loaded.tagColorDefinitions { addEdge(record, record.herd, "herd") }
        for record in loaded.animalStatusReferences { addEdge(record, record.herd, "herd") }
        for record in loaded.pastureGroups { addEdge(record, record.herd, "herd") }
        for record in loaded.pastures {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.group, "group")
        }
        for record in loaded.animals {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.pasture, "pasture")
            addEdge(record, record.sireAnimal, "sire animal")
            addEdge(record, record.damAnimal, "dam animal")
            addEdge(record, record.activeWorkingSession, "active working session")
        }
        for record in loaded.animalTags {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.animal, "animal")
        }
        for record in loaded.movements {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.animal, "animal")
        }
        for record in loaded.statusRecords {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.animal, "animal")
        }
        for record in loaded.workingProtocolTemplates { addEdge(record, record.herd, "herd") }
        for record in loaded.workingSessions {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.sourcePasture, "source pasture")
        }
        for record in loaded.workingQueueItems {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.session, "session")
            addEdge(record, record.animal, "animal")
            addEdge(record, record.collectedFromPasture, "collected from pasture")
            addEdge(record, record.destinationPasture, "destination pasture")
        }
        for record in loaded.workingTreatmentRecords {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.session, "session")
            addEdge(record, record.animal, "animal")
        }
        for record in loaded.healthRecords {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.workingSession, "working session")
            addEdge(record, record.animal, "animal")
        }
        for record in loaded.pregnancyChecks {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.workingSession, "working session")
            addEdge(record, record.animal, "animal")
            addEdge(record, record.sireAnimal, "sire animal")
        }
        for record in loaded.fieldCheckSessions {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.pasture, "pasture")
        }
        for record in loaded.fieldCheckAnimalChecks {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.session, "session")
            addEdge(record, record.animal, "animal")
        }
        for record in loaded.fieldCheckFindings {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.session, "session")
            addEdge(record, record.animal, "animal")
        }

        return Dictionary(uniqueKeysWithValues: nodes.map { node in
            let values = Array(Set(descriptors[node.localIdentifier, default: []]))
                .sorted()
            let visible = values.prefix(4).joined(separator: "; ")
            let suffix = values.count > 4 ? "; +\(values.count - 4) more" : ""
            return (node.localIdentifier, visible.isEmpty ? "none" : visible + suffix)
        })
    }

    func semanticCandidateDetail(
        node: AggregateNode,
        relationshipContext: String?,
        retainsOriginalID: Bool
    ) -> String {
        let role = retainsOriginalID
            ? "Keeps the existing public ID"
            : "Receives a replacement public ID"
        let fieldSummary = semanticFieldSummary(for: node, limit: 4)
        let relationships = relationshipContext ?? "none"
        if fieldSummary.isEmpty {
            return "\(role). Relationships: \(relationships)."
        }
        return "\(role). Details: \(fieldSummary). Relationships: \(relationships)."
    }

    func semanticCandidateChoiceContext(
        node: AggregateNode,
        relationshipContext: String?
    ) -> String {
        let fieldSummary = semanticFieldSummary(for: node, limit: 2)
        let relationships = relationshipContext ?? "none"
        if fieldSummary.isEmpty {
            return "Relationships: \(relationships)"
        }
        return "\(fieldSummary); Relationships: \(relationships)"
    }

    private func semanticFieldSummary(
        for node: AggregateNode,
        limit: Int
    ) -> String {
        let snapshot = CollaborationFieldSnapshotProvider.snapshot(for: node.aggregate)
        let values = snapshot
            .filter { key, value in
                let lowered = key.lowercased()
                return lowered != "name"
                    && !lowered.contains("publicid")
                    && value.type != .uuid
            }
            .sorted { lhs, rhs in
                let leftRank = semanticFieldRank(lhs.key)
                let rightRank = semanticFieldRank(rhs.key)
                if leftRank != rightRank { return leftRank < rightRank }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .map { key, value in
                "\(humanizedRepairLabel(key)): \(semanticDisplayValue(value))"
            }
        return values.joined(separator: ", ")
    }

    private func semanticFieldRank(_ key: String) -> Int {
        let lowered = key.lowercased()
        if lowered.contains("tag") || lowered.contains("number") { return 0 }
        if lowered.contains("color") || lowered.contains("sex") || lowered.contains("type") { return 1 }
        if lowered.contains("date") || lowered.hasSuffix("at") { return 2 }
        if lowered.contains("status") || lowered.contains("pasture") { return 3 }
        if lowered.contains("note") || lowered.contains("description") { return 4 }
        return 5
    }

    private func semanticDisplayValue(_ value: HerdSharingBridgeConflictValue) -> String {
        guard let encoded = value.encodedValue else { return "none" }
        switch value.type {
        case .null:
            return "none"
        case .bool:
            return encoded == "true" ? "Yes" : "No"
        case .date:
            guard let interval = TimeInterval(encoded) else { return shortenedSemanticValue(encoded) }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: Date(timeIntervalSinceReferenceDate: interval))
        case .string, .int, .double, .uuid:
            return shortenedSemanticValue(encoded)
        }
    }

    private func shortenedSemanticValue(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\n", with: " ")
        guard normalized.count > 72 else { return normalized }
        return String(normalized.prefix(69)) + "…"
    }

    private func humanizedRepairLabel(_ value: String) -> String {
        if value.contains(" ") {
            return value.prefix(1).uppercased() + String(value.dropFirst())
        }
        var result = ""
        for character in value {
            if character.isUppercase, !result.isEmpty {
                result.append(" ")
            }
            result.append(character)
        }
        return result.prefix(1).uppercased() + String(result.dropFirst())
    }
}
