import Foundation
import SwiftData
import XCTest

@testable import yaHerd

@MainActor

extension SwiftDataPublicIDRepairServiceTests {
    func makeTreatmentFixture(
        firstDose: WorkingTreatmentDose = WorkingTreatmentDose(
            amount: 1,
            unit: .milliliter,
            route: .subcutaneous
        ),
        secondDose: WorkingTreatmentDose,
        treatmentDose: WorkingTreatmentDose
    ) throws -> (container: ModelContainer, duplicateID: UUID) {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        // 2024-01-01 02:00 UTC intentionally crosses the calendar date in US time zones.
        let timestamp = Date(timeIntervalSince1970: 1_704_074_400)
        let duplicateID = UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")!
        let herd = Herd(
            publicID: UUID(uuidString: "10101010-AAAA-4AAA-8AAA-101010101010")!,
            name: "Treatment item repair",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(herd)
        let animal = Animal(
            publicID: UUID(uuidString: "30303030-CCCC-4CCC-8CCC-303030303030")!,
            name: "",
            tagNumber: "303",
            birthDate: timestamp,
            sex: .female
        )
        animal.herd = herd
        context.insert(animal)
        let session = WorkingSession(
            date: timestamp,
            protocolName: "Duplicate item protocol",
            protocolItems: [
                WorkingProtocolItem(
                    id: duplicateID,
                    name: "Vaccine",
                    suggestedDose: firstDose
                ),
                WorkingProtocolItem(
                    id: duplicateID,
                    name: "Vaccine",
                    suggestedDose: secondDose
                ),
            ]
        )
        session.publicID = UUID(uuidString: "20202020-BBBB-4BBB-8BBB-202020202020")!
        session.herd = herd
        context.insert(session)
        let treatment = WorkingTreatmentRecord(
            date: timestamp,
            treatmentItemID: duplicateID,
            itemName: "Vaccine",
            given: true,
            dose: treatmentDose,
            animal: animal,
            session: session
        )
        treatment.publicID = UUID(uuidString: "40404040-DDDD-4DDD-8DDD-404040404040")!
        treatment.herd = herd
        context.insert(treatment)
        try context.save()
        return (container, duplicateID)
    }

    func makeGraphDeterminismContainer(
        reverseInsertion: Bool
    ) throws -> ModelContainer {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let herdID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let duplicateAnimalID = UUID(uuidString: "CDCDCDCD-CDCD-4DCD-8DCD-CDCDCDCDCDCD")!
        let healthAID = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000001")!
        let healthBID = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000002")!
        let herd = Herd(
            publicID: herdID,
            name: "Graph determinism",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(herd)

        let animalA = Animal(
            publicID: duplicateAnimalID,
            name: "Identical",
            tagNumber: "500",
            birthDate: timestamp,
            sex: .female
        )
        animalA.herd = herd
        let animalB = Animal(
            publicID: duplicateAnimalID,
            name: "Identical",
            tagNumber: "500",
            birthDate: timestamp,
            sex: .female
        )
        animalB.herd = herd
        let healthA = HealthRecord(
            publicID: healthAID,
            date: timestamp,
            treatment: "Identical treatment",
            animal: animalA
        )
        healthA.herd = herd
        let healthB = HealthRecord(
            publicID: healthBID,
            date: timestamp,
            treatment: "Identical treatment",
            animal: animalB
        )
        healthB.herd = herd

        if reverseInsertion {
            context.insert(animalB)
            context.insert(healthB)
            context.insert(animalA)
            context.insert(healthA)
        } else {
            context.insert(animalA)
            context.insert(healthA)
            context.insert(animalB)
            context.insert(healthB)
        }
        try context.save()
        return container
    }

    func exportGraphSignature(
        from container: ModelContainer
    ) async throws -> [String] {
        let context = ModelContext(container)
        let herd = try XCTUnwrap(context.fetch(FetchDescriptor<Herd>()).first)
        let export = try await SwiftDataHerdSharingActor(
            modelContainer: container
        ).makeExport(
            for: herd.toSummary(),
            storeDescription: "graph comparison"
        )
        return HerdSharingBridgeStep.entitySteps.flatMap { step in
            export.snapshot.records(for: step).map { record in
                let attributes = record.attributes
                    .filter { !Self.volatileBridgeAttributes.contains($0.key) }
                    .map { "\($0.key)=\(attributeSignature($0.value))" }
                    .sorted()
                    .joined(separator: ",")
                return "\(String(describing: step))|\(record.publicID)|\(attributes)"
            }
        }.sorted()
    }

    func attributeSignature(
        _ value: HerdSharingBridgeAttributeValue
    ) -> String {
        switch value {
        case .null: "null"
        case .string(let value): "string:\(value)"
        case .date(let value): "date:\(value.timeIntervalSinceReferenceDate)"
        case .data(let value): "data:\(value.base64EncodedString())"
        case .integer(let value): "integer:\(value)"
        case .double(let value): "double:\(value)"
        case .boolean(let value): "boolean:\(value)"
        }
    }

    static let volatileBridgeAttributes: Set<String> = [
        "lastMirroredAt",
        "modifiedAt",
        "revision",
        "modifiedByParticipantID",
        "modifiedByDeviceID",
        "baseRevision",
        "baseFieldValuesJSON",
        "currentFieldValuesJSON",
    ]
}
