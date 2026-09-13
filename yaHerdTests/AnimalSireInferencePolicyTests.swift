import XCTest
@testable import yaHerd

@MainActor
final class AnimalSireInferencePolicyTests: XCTestCase {
    func testReturnsOnlyEligibleBullInPasture() {
        let pastureID = UUID()
        let eligibleBullID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let candidates = [
            makeCandidate(
                id: eligibleBullID,
                pastureID: pastureID,
                sex: .male,
                birthDate: Calendar.current.date(byAdding: .year, value: -3, to: now)!,
                animalType: .bull
            ),
            makeCandidate(
                pastureID: pastureID,
                sex: .female,
                birthDate: Calendar.current.date(byAdding: .year, value: -3, to: now)!,
                animalType: .cow
            ),
            makeCandidate(
                pastureID: UUID(),
                sex: .male,
                birthDate: Calendar.current.date(byAdding: .year, value: -3, to: now)!,
                animalType: .bull
            )
        ]

        let inferredID = AnimalSireInferencePolicy().inferSireID(
            from: candidates,
            pastureID: pastureID,
            excluding: nil,
            asOf: now
        )

        XCTAssertEqual(inferredID, eligibleBullID)
    }

    func testReturnsNilWhenMultipleEligibleBullsExist() {
        let pastureID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let birthDate = Calendar.current.date(byAdding: .year, value: -3, to: now)!
        let candidates = [
            makeCandidate(pastureID: pastureID, sex: .male, birthDate: birthDate, animalType: .bull),
            makeCandidate(pastureID: pastureID, sex: .male, birthDate: birthDate, animalType: .bull)
        ]

        XCTAssertNil(
            AnimalSireInferencePolicy().inferSireID(
                from: candidates,
                pastureID: pastureID,
                excluding: nil,
                asOf: now
            )
        )
    }

    func testIgnoresExcludedArchivedAndInactiveCandidates() {
        let pastureID = UUID()
        let excludedID = UUID()
        let eligibleID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let birthDate = Calendar.current.date(byAdding: .year, value: -3, to: now)!
        let candidates = [
            makeCandidate(id: excludedID, pastureID: pastureID, sex: .male, birthDate: birthDate, animalType: .bull),
            makeCandidate(pastureID: pastureID, sex: .male, birthDate: birthDate, status: .sold, animalType: .bull),
            makeCandidate(pastureID: pastureID, sex: .male, birthDate: birthDate, isArchived: true, animalType: .bull),
            makeCandidate(id: eligibleID, pastureID: pastureID, sex: .male, birthDate: birthDate, animalType: .bull)
        ]

        let inferredID = AnimalSireInferencePolicy().inferSireID(
            from: candidates,
            pastureID: pastureID,
            excluding: excludedID,
            asOf: now
        )

        XCTAssertEqual(inferredID, eligibleID)
    }

    private func makeCandidate(
        id: UUID = UUID(),
        pastureID: UUID?,
        sex: Sex,
        birthDate: Date,
        status: AnimalStatus = .active,
        isArchived: Bool = false,
        animalType: AnimalType
    ) -> AnimalSireCandidate {
        AnimalSireCandidate(
            id: id,
            pastureID: pastureID,
            sex: sex,
            birthDate: birthDate,
            status: status,
            isArchived: isArchived,
            animalType: animalType
        )
    }
}
