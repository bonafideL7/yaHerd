import XCTest
@testable import yaHerd

final class WorkingCollectAnimalsEligibilityTests: XCTestCase {
    func testExistingSessionAnimalsAreExcludedWhileNewPastureAnimalsRemainAvailable() {
        let sourcePastureID = UUID()
        let existingAnimalID = UUID()
        let newAnimalID = UUID()

        let candidates = WorkingCollectAnimalsEligibility.candidates(
            from: [
                makeAnimalSummary(
                    id: existingAnimalID,
                    displayTagNumber: "12",
                    pastureID: sourcePastureID
                ),
                makeAnimalSummary(
                    id: newAnimalID,
                    displayTagNumber: "34",
                    pastureID: sourcePastureID
                )
            ],
            sourcePastureID: sourcePastureID,
            existingAnimalIDs: [existingAnimalID]
        )

        XCTAssertEqual(candidates.map(\.id), [newAnimalID])
    }

    private func makeAnimalSummary(
        id: UUID,
        displayTagNumber: String,
        pastureID: UUID
    ) -> AnimalSummary {
        AnimalSummary(
            id: id,
            name: "Cow \(displayTagNumber)",
            displayTagNumber: displayTagNumber,
            displayTagColorID: nil,
            damDisplayTagNumber: nil,
            damDisplayTagColorID: nil,
            sex: .female,
            animalType: .cow,
            firstDistinguishingFeature: nil,
            birthDate: .distantPast,
            status: .active,
            isArchived: false,
            pastureID: pastureID,
            pastureName: "North",
            location: .pasture
        )
    }
}
