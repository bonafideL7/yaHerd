import XCTest
@testable import yaHerd

final class WorkingAnimalWorkTimestampTests: XCTestCase {
    func testNewWorkUsesCurrentSaveTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(
            WorkingAnimalWorkTimestamp.resolve(existingCompletedAt: nil, now: now),
            now
        )
    }

    func testHistoricalEditPreservesExistingCompletionTime() {
        let existing = Date(timeIntervalSince1970: 1_700_000_000)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(
            WorkingAnimalWorkTimestamp.resolve(existingCompletedAt: existing, now: now),
            existing
        )
    }

    func testPregnancyDueDateUsesCurrentWorkDateForBackdatedSession() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let sessionDate = Date(timeIntervalSince1970: 1_700_000_000)
        let saveTime = Date(timeIntervalSince1970: 1_800_000_000)
        let estimatedDaysPregnant = 200
        let workDate = WorkingAnimalWorkTimestamp.resolve(
            existingCompletedAt: nil,
            now: saveTime
        )

        let dueDate = try XCTUnwrap(
            WorkingPregnancyDueDateCalculator.calculate(
                estimatedDaysPregnant: estimatedDaysPregnant,
                workDate: workDate,
                calendar: calendar
            )
        )
        let expected = try XCTUnwrap(
            calendar.date(
                byAdding: .day,
                value: WorkingConstants.gestationDays - estimatedDaysPregnant,
                to: saveTime
            )
        )
        let sessionAnchoredDate = try XCTUnwrap(
            calendar.date(
                byAdding: .day,
                value: WorkingConstants.gestationDays - estimatedDaysPregnant,
                to: sessionDate
            )
        )

        XCTAssertEqual(dueDate, expected)
        XCTAssertNotEqual(dueDate, sessionAnchoredDate)
    }

    func testPregnancyDueDatePreservesHistoricalCompletionAnchor() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let existingCompletion = Date(timeIntervalSince1970: 1_700_000_000)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let estimatedDaysPregnant = 150
        let workDate = WorkingAnimalWorkTimestamp.resolve(
            existingCompletedAt: existingCompletion,
            now: now
        )

        let dueDate = try XCTUnwrap(
            WorkingPregnancyDueDateCalculator.calculate(
                estimatedDaysPregnant: estimatedDaysPregnant,
                workDate: workDate,
                calendar: calendar
            )
        )
        let expected = try XCTUnwrap(
            calendar.date(
                byAdding: .day,
                value: WorkingConstants.gestationDays - estimatedDaysPregnant,
                to: existingCompletion
            )
        )

        XCTAssertEqual(dueDate, expected)
    }

    func testAutomaticallyCalculatedDueDateReanchorsToFinalSaveTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let previewTime = Date(timeIntervalSince1970: 1_800_000_000)
        let saveTime = Date(timeIntervalSince1970: 1_800_086_400)
        let estimatedDaysPregnant = 200
        let previewDueDate = try XCTUnwrap(
            WorkingPregnancyDueDateCalculator.calculate(
                estimatedDaysPregnant: estimatedDaysPregnant,
                workDate: previewTime,
                calendar: calendar
            )
        )

        let savedDueDate = WorkingPregnancyDueDateCalculator.resolveForSave(
            displayedDueDate: previewDueDate,
            automaticallyCalculatedDueDate: previewDueDate,
            estimatedDaysPregnant: estimatedDaysPregnant,
            workDate: saveTime,
            calendar: calendar
        )
        let expected = try XCTUnwrap(
            calendar.date(
                byAdding: .day,
                value: WorkingConstants.gestationDays - estimatedDaysPregnant,
                to: saveTime
            )
        )

        XCTAssertEqual(savedDueDate, expected)
    }

    func testSeedingSavedPregnancyCheckPreservesManualDueDate() {
        let savedDueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fallbackDate = Date(timeIntervalSince1970: 1_700_000_000)

        let state = WorkingPregnancyDueDateFormState.seeded(
            estimatedDaysPregnant: 175,
            savedDueDate: savedDueDate,
            fallbackDate: fallbackDate
        )

        XCTAssertEqual(state.estimatedDaysText, "175")
        XCTAssertEqual(state.dueDate, savedDueDate)
        XCTAssertNil(state.automaticallyCalculatedDueDate)
    }

    func testManuallyAdjustedDueDateIsPreservedAtSave() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let previewTime = Date(timeIntervalSince1970: 1_800_000_000)
        let saveTime = Date(timeIntervalSince1970: 1_800_086_400)
        let previewDueDate = try XCTUnwrap(
            WorkingPregnancyDueDateCalculator.calculate(
                estimatedDaysPregnant: 200,
                workDate: previewTime,
                calendar: calendar
            )
        )
        let manuallyAdjustedDueDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: 3, to: previewDueDate)
        )

        let savedDueDate = WorkingPregnancyDueDateCalculator.resolveForSave(
            displayedDueDate: manuallyAdjustedDueDate,
            automaticallyCalculatedDueDate: previewDueDate,
            estimatedDaysPregnant: 200,
            workDate: saveTime,
            calendar: calendar
        )

        XCTAssertEqual(savedDueDate, manuallyAdjustedDueDate)
    }

}
