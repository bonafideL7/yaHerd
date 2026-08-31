import Foundation
import XCTest
@testable import yaHerd

final class DraftRefreshPolicyTests: XCTestCase {
    private let normalizeWhitespace: (String) -> String = {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testUneditedDraftAdoptsRefreshedValue() {
        let result = DraftRefreshPolicy.reconciledValue(
            draft: "Original",
            previouslyLoadedValue: "Original",
            refreshedValue: "Imported",
            isSameRecord: true,
            normalize: normalizeWhitespace
        )

        XCTAssertEqual(result, "Imported")
    }

    func testEditedDraftIsPreservedForSameRecord() {
        let result = DraftRefreshPolicy.reconciledValue(
            draft: "Local edit",
            previouslyLoadedValue: "Original",
            refreshedValue: "Imported",
            isSameRecord: true,
            normalize: normalizeWhitespace
        )

        XCTAssertEqual(result, "Local edit")
    }

    func testRecordIdentityMismatchResetsEditedDraft() {
        let result = DraftRefreshPolicy.reconciledValue(
            draft: "Local edit",
            previouslyLoadedValue: "Original",
            refreshedValue: "Other record",
            isSameRecord: false,
            normalize: normalizeWhitespace
        )

        XCTAssertEqual(result, "Other record")
    }

    func testWhitespaceEquivalentDraftIsTreatedAsUnedited() {
        let result = DraftRefreshPolicy.reconciledValue(
            draft: "  Original\n",
            previouslyLoadedValue: "Original",
            refreshedValue: "Imported",
            isSameRecord: true,
            normalize: normalizeWhitespace
        )

        XCTAssertEqual(result, "Imported")
    }

    func testMissingPreviousValueInitializesFromRefresh() {
        let result = DraftRefreshPolicy.reconciledValue(
            draft: "Stale",
            previouslyLoadedValue: nil,
            refreshedValue: "Loaded",
            isSameRecord: true,
            normalize: normalizeWhitespace
        )

        XCTAssertEqual(result, "Loaded")
    }
}
