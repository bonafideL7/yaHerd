import XCTest
@testable import yaHerd

@MainActor
final class CloudKitHerdSelectionDecisionTests: XCTestCase {
    private func herd(_ id: UUID = UUID(), category: AccessibleHerd.Category) -> AccessibleHerd {
        AccessibleHerd(
            summary: HerdSummary(
                publicID: id,
                name: "Herd",
                createdAt: Date(timeIntervalSince1970: 100),
                updatedAt: Date(timeIntervalSince1970: 100)
            ),
            category: category
        )
    }

    func testMultipleOwnedAndJoinedHerdsRequireAnExplicitChoice() {
        let owned = herd(category: .owned)
        let joined = herd(category: .shared)
        XCTAssertEqual(
            CloudKitHerdSelectionDecision.resolve(
                available: [owned, joined], explicit: nil, remembered: nil
            ),
            .choose
        )
        XCTAssertEqual(
            CloudKitHerdSelectionDecision.resolve(
                available: [owned, joined], explicit: nil, remembered: joined.id
            ),
            .open(joined.id)
        )
    }

    func testRemovedRememberedHerdNeverFallsBackToAnotherHerd() {
        XCTAssertEqual(
            CloudKitHerdSelectionDecision.resolve(
                available: [herd(category: .owned)],
                explicit: nil,
                remembered: UUID()
            ),
            .choose
        )
    }

    func testExplicitUnavailableSelectionWaitsForImportWithoutCreatingAReplacement() {
        let missing = UUID()
        XCTAssertEqual(
            CloudKitHerdSelectionDecision.resolve(
                available: [], explicit: missing, remembered: nil
            ),
            .waitForImport(missing)
        )
    }

    func testSingleDiscoveredHerdCanOpenWithoutSavedPreference() {
        let only = herd(category: .shared)
        XCTAssertEqual(
            CloudKitHerdSelectionDecision.resolve(
                available: [only], explicit: nil, remembered: nil
            ),
            .open(only.id)
        )
        XCTAssertEqual(
            CloudKitHerdSelectionDecision.resolve(
                available: [], explicit: nil, remembered: nil
            ),
            .choose
        )
    }

    func testSavedSelectionIsDeviceLocalAndInvalidValuesAreIgnored() {
        let suite = "CloudKitHerdSelectionDecisionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        XCTAssertNil(CloudKitSelectedHerdPreference.load(from: defaults))
        CloudKitSelectedHerdPreference.save(id, to: defaults)
        XCTAssertEqual(CloudKitSelectedHerdPreference.load(from: defaults), id)
        defaults.set("invalid", forKey: CloudKitSelectedHerdPreference.key)
        XCTAssertNil(CloudKitSelectedHerdPreference.load(from: defaults))
    }
}
