import XCTest
@testable import yaHerd

final class PastureInputValidatorTests: XCTestCase {
    func testValidateNormalizesNameAndReturnsInput() throws {
        let validator = PastureInputValidator { _, _ in false }

        let result = try validator.validate(
            input: PastureInput(
                name: "  North Pasture  ",
                acreage: 12,
                usableAcreage: 10,
                targetAcresPerHead: 2
            )
        )

        XCTAssertEqual(result.name, "North Pasture")
        XCTAssertEqual(result.acreage, 12)
        XCTAssertEqual(result.usableAcreage, 10)
        XCTAssertEqual(result.targetAcresPerHead, 2)
    }

    func testValidateRejectsEmptyName() {
        let validator = PastureInputValidator { _, _ in false }

        XCTAssertThrowsError(
            try validator.validate(input: PastureInput(name: "  \n", acreage: nil, usableAcreage: nil, targetAcresPerHead: nil))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .emptyName)
        }
    }

    func testValidateRejectsInvalidAcreage() {
        let validator = PastureInputValidator { _, _ in false }

        XCTAssertThrowsError(
            try validator.validate(input: PastureInput(name: "North", acreage: 0, usableAcreage: nil, targetAcresPerHead: nil))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .invalidAcreage)
        }
    }

    func testValidateRejectsInvalidUsableAcreage() {
        let validator = PastureInputValidator { _, _ in false }

        XCTAssertThrowsError(
            try validator.validate(input: PastureInput(name: "North", acreage: 10, usableAcreage: -1, targetAcresPerHead: nil))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .invalidUsableAcreage)
        }
    }

    func testValidateRejectsInvalidTargetAcresPerHead() {
        let validator = PastureInputValidator { _, _ in false }

        XCTAssertThrowsError(
            try validator.validate(input: PastureInput(name: "North", acreage: 10, usableAcreage: 8, targetAcresPerHead: 0))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .invalidTargetAcresPerHead)
        }
    }

    func testValidateRejectsUsableAcreageGreaterThanTotalAcreage() {
        let validator = PastureInputValidator { _, _ in false }

        XCTAssertThrowsError(
            try validator.validate(input: PastureInput(name: "North", acreage: 10, usableAcreage: 11, targetAcresPerHead: 2))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .usableAcreageExceedsAcreage)
        }
    }

    func testValidateRejectsDuplicateNameAfterTrimming() {
        let validator = PastureInputValidator { name, _ in
            name == "North"
        }

        XCTAssertThrowsError(
            try validator.validate(input: PastureInput(name: " North ", acreage: nil, usableAcreage: nil, targetAcresPerHead: nil))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .duplicateName("North"))
        }
    }

    func testValidatePassesExcludedIDToDuplicateCheck() throws {
        let excludedID = UUID()
        var receivedID: UUID?
        let validator = PastureInputValidator { _, id in
            receivedID = id
            return false
        }

        _ = try validator.validate(
            input: PastureInput(name: "North", acreage: nil, usableAcreage: nil, targetAcresPerHead: nil),
            excluding: excludedID
        )

        XCTAssertEqual(receivedID, excludedID)
    }
}
