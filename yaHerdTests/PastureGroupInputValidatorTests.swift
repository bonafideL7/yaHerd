import XCTest
@testable import yaHerd

final class PastureGroupInputValidatorTests: XCTestCase {
    func testValidateNormalizesNameAndReturnsInput() throws {
        let validator = PastureGroupInputValidator { _, _ in false }

        let result = try validator.validate(input: PastureGroupInput(name: "  Spring Rotation  ", grazeDays: 7, restDays: 21))

        XCTAssertEqual(result.name, "Spring Rotation")
        XCTAssertEqual(result.grazeDays, 7)
        XCTAssertEqual(result.restDays, 21)
    }

    func testValidateRejectsEmptyName() {
        let validator = PastureGroupInputValidator { _, _ in false }

        XCTAssertThrowsError(
            try validator.validate(input: PastureGroupInput(name: " ", grazeDays: 7, restDays: 21))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .emptyName)
        }
    }

    func testValidateRejectsGrazeDaysOutsideRange() {
        let validator = PastureGroupInputValidator { _, _ in false }

        XCTAssertThrowsError(
            try validator.validate(input: PastureGroupInput(name: "Spring", grazeDays: 0, restDays: 21))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .invalidGrazeDays)
        }

        XCTAssertThrowsError(
            try validator.validate(input: PastureGroupInput(name: "Spring", grazeDays: 31, restDays: 21))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .invalidGrazeDays)
        }
    }

    func testValidateRejectsRestDaysOutsideRange() {
        let validator = PastureGroupInputValidator { _, _ in false }

        XCTAssertThrowsError(
            try validator.validate(input: PastureGroupInput(name: "Spring", grazeDays: 7, restDays: 6))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .invalidRestDays)
        }

        XCTAssertThrowsError(
            try validator.validate(input: PastureGroupInput(name: "Spring", grazeDays: 7, restDays: 91))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .invalidRestDays)
        }
    }

    func testValidateRejectsDuplicateNameAfterTrimming() {
        let validator = PastureGroupInputValidator { name, _ in
            name == "Spring"
        }

        XCTAssertThrowsError(
            try validator.validate(input: PastureGroupInput(name: " Spring ", grazeDays: 7, restDays: 21))
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .duplicateName("Spring"))
        }
    }

    func testCanAttemptSaveRequiresValidNameAndRanges() {
        XCTAssertTrue(PastureGroupInputValidator.canAttemptSave(name: "Spring", grazeDays: 1, restDays: 7))
        XCTAssertTrue(PastureGroupInputValidator.canAttemptSave(name: "Spring", grazeDays: 30, restDays: 90))
        XCTAssertFalse(PastureGroupInputValidator.canAttemptSave(name: " ", grazeDays: 7, restDays: 21))
        XCTAssertFalse(PastureGroupInputValidator.canAttemptSave(name: "Spring", grazeDays: 0, restDays: 21))
        XCTAssertFalse(PastureGroupInputValidator.canAttemptSave(name: "Spring", grazeDays: 7, restDays: 91))
    }
}
