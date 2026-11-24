import XCTest
@testable import yaHerd

@MainActor
final class AnimalInlineEntryViewModelTests: XCTestCase {
    func testInitialBirthDateUsesInjectedDateProviderStartOfDay() {
        let fixedNow = Date(timeIntervalSince1970: 1_782_567_000)
        let calendar = fixedCalendar
        let viewModel = AnimalInlineEntryViewModel(
            dateProvider: FixedDateProvider(now: fixedNow),
            calendar: calendar
        )

        XCTAssertEqual(viewModel.birthDate, calendar.startOfDay(for: fixedNow))
    }

    func testBeginNewResetsBirthDateUsingInjectedDateProvider() {
        let fixedNow = Date(timeIntervalSince1970: 1_782_567_000)
        let calendar = fixedCalendar
        let viewModel = AnimalInlineEntryViewModel(
            dateProvider: FixedDateProvider(now: fixedNow),
            calendar: calendar
        )
        viewModel.birthDate = .distantPast

        viewModel.beginNew()

        XCTAssertEqual(viewModel.birthDate, calendar.startOfDay(for: fixedNow))
    }

    func testCancelResetsBirthDateUsingInjectedDateProvider() {
        let fixedNow = Date(timeIntervalSince1970: 1_782_567_000)
        let calendar = fixedCalendar
        let viewModel = AnimalInlineEntryViewModel(
            dateProvider: FixedDateProvider(now: fixedNow),
            calendar: calendar
        )
        viewModel.birthDate = .distantPast

        viewModel.cancel()

        XCTAssertEqual(viewModel.birthDate, calendar.startOfDay(for: fixedNow))
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private struct FixedDateProvider: DateProviding {
    let now: Date
}
