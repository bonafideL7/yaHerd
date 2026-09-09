import Foundation
import SwiftData

extension DeterministicSwiftDataPublicIDRepairService {
    func relationshipFingerprints(
        loaded: LoadedRecords,
        nodes: [AggregateNode]
    ) -> [String: String] {
        var nodeByObject: [ObjectIdentifier: AggregateNode] = [:]
        nodeByObject.reserveCapacity(nodes.count)
        for node in nodes {
            nodeByObject[ObjectIdentifier(node.aggregate)] = node
        }
        var descriptors: [String: [String]] = [:]

        func portableSemantic(_ node: AggregateNode) -> String {
            [
                node.entityType.rawValue,
                node.readPublicID().uuidString.lowercased(),
                deterministicDigest(node.snapshotKey),
            ].joined(separator: "|")
        }

        func addEdge(
            _ source: (any CollaborativelyMutableAggregate)?,
            _ target: (any CollaborativelyMutableAggregate)?,
            _ label: String
        ) {
            guard let source, let target,
                  let sourceNode = nodeByObject[ObjectIdentifier(source)],
                  let targetNode = nodeByObject[ObjectIdentifier(target)]
            else { return }
            let sourceSemantic = portableSemantic(sourceNode)
            let targetSemantic = portableSemantic(targetNode)
            descriptors[sourceNode.localIdentifier, default: []].append(
                "out|\(label)|\(targetSemantic)"
            )
            descriptors[targetNode.localIdentifier, default: []].append(
                "in|\(label)|\(sourceSemantic)"
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
            addEdge(record, record.sireAnimal, "sireAnimal")
            addEdge(record, record.damAnimal, "damAnimal")
            addEdge(record, record.activeWorkingSession, "activeWorkingSession")
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
            addEdge(record, record.sourcePasture, "sourcePasture")
        }
        for record in loaded.workingQueueItems {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.session, "session")
            addEdge(record, record.animal, "animal")
            addEdge(record, record.collectedFromPasture, "collectedFromPasture")
            addEdge(record, record.destinationPasture, "destinationPasture")
        }
        for record in loaded.workingTreatmentRecords {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.session, "session")
            addEdge(record, record.animal, "animal")
        }
        for record in loaded.healthRecords {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.workingSession, "workingSession")
            addEdge(record, record.animal, "animal")
        }
        for record in loaded.pregnancyChecks {
            addEdge(record, record.herd, "herd")
            addEdge(record, record.workingSession, "workingSession")
            addEdge(record, record.animal, "animal")
            addEdge(record, record.sireAnimal, "sireAnimal")
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

        var result: [String: String] = [:]
        result.reserveCapacity(nodes.count)
        for node in nodes {
            let key = descriptors[node.localIdentifier, default: []]
                .sorted()
                .joined(separator: "|")
            result[node.localIdentifier] = deterministicDigest(key)
        }
        return result
    }

}
