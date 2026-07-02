import XCTest
import SwiftData
@testable import yaHerd

final class FieldCheckHistoricalSnapshotTests: XCTestCase {
    func testSessionDetailUsesCheckStartSnapshotsAfterPastureAndAnimalChange() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)

        let pasture = Pasture(name: "North")
        let animal = Animal(
            name: "Daisy",
            tagNumber: "101",
            tagColorID: UUID(uuidString: "00000000-0000-0000-0000-000000000101"),
            birthDate: Date(timeIntervalSince1970: 0),
            status: .active,
            pasture: pasture,
            sex: .female
        )
        animal.pasture = pasture
        context.insert(pasture)
        context.insert(animal)
        try context.save()

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 1_000),
                notes: ""
            )
        )

        pasture.name = "South"
        animal.name = "Changed"
        animal.tagNumber = "999"
        animal.tagColorID = UUID(uuidString: "00000000-0000-0000-0000-000000000999")
        animal.sex = .male
        try context.save()

        let detail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let check = try XCTUnwrap(detail.animalChecks.first)

        XCTAssertEqual(detail.pastureName, "North")
        XCTAssertEqual(check.displayTagNumber, "101")
        XCTAssertEqual(check.displayTagColorID, UUID(uuidString: "00000000-0000-0000-0000-000000000101"))
        XCTAssertEqual(check.animalName, "Daisy")
        XCTAssertEqual(check.animalSex, .female)
        XCTAssertEqual(check.animalType, .heifer)
    }

    func testQuickCountCapacityUsesSnapshotAnimalTypeAfterAnimalTypeChanges() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)

        let pasture = Pasture(name: "North")
        let animal = Animal(
            name: "Daisy",
            tagNumber: "101",
            birthDate: Date(timeIntervalSince1970: 0),
            status: .active,
            pasture: pasture,
            sex: .female
        )
        animal.pasture = pasture
        context.insert(pasture)
        context.insert(animal)
        try context.save()

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 1_000),
                notes: ""
            )
        )

        animal.sex = .male
        try context.save()

        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.heifer: 1, .bull: 1])

        let detail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertEqual(detail.quickHeiferCount, 1)
        XCTAssertEqual(detail.quickBullCount, 0)
        XCTAssertEqual(detail.totalSeen, 1)
    }

    func testFindingUsesAnimalAndPastureSnapshotsAfterRecordsChange() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)

        let pasture = Pasture(name: "North")
        let animal = Animal(
            name: "Daisy",
            tagNumber: "101",
            tagColorID: UUID(uuidString: "00000000-0000-0000-0000-000000000101"),
            birthDate: Date(timeIntervalSince1970: 0),
            status: .active,
            pasture: pasture,
            sex: .female
        )
        animal.pasture = pasture
        context.insert(pasture)
        context.insert(animal)
        try context.save()

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 1_000),
                notes: ""
            )
        )
        let detail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let animalID = try XCTUnwrap(detail.animalChecks.first?.animalID)

        try repository.addFinding(
            sessionID: sessionID,
            input: FieldCheckFindingInput(
                recordedAt: Date(timeIntervalSince1970: 2_000),
                type: .pinkEye,
                severity: .warning,
                status: .open,
                note: "Left eye.",
                animalID: animalID
            )
        )

        pasture.name = "South"
        animal.name = "Changed"
        animal.tagNumber = "999"
        animal.tagColorID = UUID(uuidString: "00000000-0000-0000-0000-000000000999")
        try context.save()

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let finding = try XCTUnwrap(updatedDetail.findings.first)

        XCTAssertEqual(finding.animalDisplayTagNumber, "101")
        XCTAssertEqual(finding.animalDisplayTagColorID, UUID(uuidString: "00000000-0000-0000-0000-000000000101"))
        XCTAssertEqual(finding.pastureName, "North")
    }

    func testDamTagUsesCheckStartSnapshotAfterDamChanges() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)

        let pasture = Pasture(name: "North")
        let dam = Animal(
            name: "Dam",
            tagNumber: "D1",
            tagColorID: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1"),
            birthDate: Date(timeIntervalSince1970: 0),
            status: .active,
            pasture: pasture,
            sex: .female
        )
        let calf = Animal(
            name: "Calf",
            tagNumber: "C1",
            birthDate: Date(),
            status: .active,
            sireAnimal: nil,
            damAnimal: dam,
            pasture: pasture,
            sex: .female
        )
        dam.pasture = pasture
        calf.pasture = pasture
        context.insert(pasture)
        context.insert(dam)
        context.insert(calf)
        try context.save()

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 1_000),
                notes: ""
            )
        )

        dam.tagNumber = "D2"
        dam.tagColorID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")
        try context.save()

        let detail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let calfCheck = try XCTUnwrap(detail.animalChecks.first { $0.displayTagNumber == "C1" })

        XCTAssertEqual(calfCheck.damDisplayTagNumber, "D1")
        XCTAssertEqual(calfCheck.damDisplayTagColorID, UUID(uuidString: "00000000-0000-0000-0000-0000000000D1"))
    }
}
