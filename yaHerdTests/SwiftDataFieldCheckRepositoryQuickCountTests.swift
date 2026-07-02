import XCTest
import SwiftData
@testable import yaHerd

final class SwiftDataFieldCheckRepositoryQuickCountTests: XCTestCase {
    func testCountingAnimalNormalizesStoredQuickCountForSameAnimalType() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let pasture = try makePastureWithAnimals(context: context, animalCount: 3, sex: .female)

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 0),
                notes: ""
            )
        )
        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.heifer: 3])

        let initialDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let animalCheckID = try XCTUnwrap(initialDetail.animalChecks.first?.id)

        try repository.setAnimalCheckCounted(
            sessionID: sessionID,
            animalCheckID: animalCheckID,
            isCounted: true
        )

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertEqual(updatedDetail.quickHeiferCount, 2)
        XCTAssertEqual(updatedDetail.quickAnimalTypeCounts[.heifer], 2)
        XCTAssertEqual(updatedDetail.individuallyVerifiedCount, 1)
        XCTAssertEqual(updatedDetail.totalSeen, 3)
        XCTAssertEqual(updatedDetail.countVariance, 0)
    }

    func testMarkingAnimalMissingNormalizesStoredQuickCountForSameAnimalType() throws {
        let container = try TestSupport.makeModelContainer()
        let context = ModelContext(container)
        let repository = SwiftDataFieldCheckRepository(context: context)
        let pasture = try makePastureWithAnimals(context: context, animalCount: 3, sex: .female)

        let sessionID = try repository.createSession(
            input: FieldCheckSessionStartInput(
                pastureID: pasture.publicID,
                startedAt: Date(timeIntervalSince1970: 0),
                notes: ""
            )
        )
        try repository.updateQuickAnimalTypeCounts(sessionID: sessionID, counts: [.heifer: 3])

        let initialDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        let animalCheckID = try XCTUnwrap(initialDetail.animalChecks.first?.id)

        try repository.setAnimalCheckMissing(
            sessionID: sessionID,
            animalCheckID: animalCheckID,
            isMissing: true
        )

        let updatedDetail = try XCTUnwrap(repository.fetchSessionDetail(id: sessionID))
        XCTAssertEqual(updatedDetail.quickHeiferCount, 2)
        XCTAssertEqual(updatedDetail.quickAnimalTypeCounts[.heifer], 2)
        XCTAssertEqual(updatedDetail.individuallyVerifiedCount, 0)
        XCTAssertEqual(updatedDetail.totalSeen, 2)
        XCTAssertEqual(updatedDetail.missingAnimalCount, 1)
    }

    private func makePastureWithAnimals(
        context: ModelContext,
        animalCount: Int,
        sex: Sex
    ) throws -> Pasture {
        let pasture = Pasture(name: "North")
        context.insert(pasture)

        for index in 1...animalCount {
            let animal = Animal(
                name: "Heifer \(index)",
                tagNumber: "\(index)",
                birthDate: Date(timeIntervalSince1970: 0),
                status: .active,
                pasture: pasture,
                sex: sex
            )
            animal.pasture = pasture
            context.insert(animal)
        }

        try context.save()
        return pasture
    }
}
