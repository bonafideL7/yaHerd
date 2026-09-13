import Foundation
import XCTest
@testable import yaHerd

final class FieldCheckSessionIdentityRefreshTests: XCTestCase {
    func testMissingRefreshedSessionInvalidatesPresentation() {
        XCTAssertTrue(
            FieldCheckSessionIdentitySnapshot.invalidatesPresentation(
                refreshedSession: nil,
                presentedFinding: nil,
                presentedAnimalID: nil
            )
        )
    }

    func testExistingSessionWithoutPresentedIdentityPreservesPresentation() {
        let snapshot = FieldCheckSessionIdentitySnapshot(
            detail: FieldCheckSessionDetailSnapshot(
                id: UUID(),
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: nil,
                notes: "",
                pastureID: UUID(),
                pastureName: "North",
                expectedHeadCountSnapshot: 0,
                quickCowCount: 0,
                quickHeiferCount: 0,
                quickCalfCount: 0,
                quickBullCount: 0,
                quickSteerCount: 0,
                animalChecks: [],
                findings: []
            )
        )

        XCTAssertFalse(
            FieldCheckSessionIdentitySnapshot.invalidatesPresentation(
                refreshedSession: snapshot,
                presentedFinding: nil,
                presentedAnimalID: nil
            )
        )
    }
}
