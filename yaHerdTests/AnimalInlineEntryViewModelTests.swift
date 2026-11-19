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

        viewModel.beginNew(selection: AppCurrentHerdSelection(currentHerdID: UUID()))

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


    func testInlineCreateRejectsChangedOrRevokedHerdBeforeRepositoryWrite() {
        for change in HerdChange.allCases {
            let herdID = UUID()
            let selection = AppCurrentHerdSelection(currentHerdID: herdID)
            let model = AnimalInlineEntryViewModel()
            let repository = InlineAnimalWriteProbe()
            model.beginNew(selection: selection)
            model.text = "Daisy"

            change.apply(to: selection, originalHerdID: herdID)

            XCTAssertThrowsError(
                try model.commit(
                    startNewEntryAfterCreate: false,
                    colors: [],
                    defaultTagColorID: nil,
                    using: repository,
                    selection: selection
                )
            ) { error in
                XCTAssertTrue(error is CancellationError)
            }
            XCTAssertEqual(repository.createCount, 0, "Unexpected write after \\(change)")
            XCTAssertTrue(model.isActive, "The rejected draft must remain available")
        }
    }

    func testInlineEditRejectsChangedOrRevokedHerdBeforeRepositoryRead() {
        for change in HerdChange.allCases {
            let herdID = UUID()
            let selection = AppCurrentHerdSelection(currentHerdID: herdID)
            let model = AnimalInlineEntryViewModel()
            let repository = InlineAnimalWriteProbe()
            model.beginNew(selection: selection)
            model.editingAnimalID = UUID()
            model.text = "Daisy"

            change.apply(to: selection, originalHerdID: herdID)

            XCTAssertThrowsError(
                try model.commit(
                    startNewEntryAfterCreate: false,
                    colors: [],
                    defaultTagColorID: nil,
                    using: repository,
                    selection: selection
                )
            ) { error in
                XCTAssertTrue(error is CancellationError)
            }
            XCTAssertEqual(repository.fetchCount, 0, "Unexpected read after \\(change)")
            XCTAssertEqual(repository.updateCount, 0)
        }
    }

    func testInlineCreateStillCallsRepositoryUnderUnchangedSelection() {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = AnimalInlineEntryViewModel()
        let repository = InlineAnimalWriteProbe()
        model.beginNew(selection: selection)
        model.text = "Daisy"

        XCTAssertThrowsError(
            try model.commit(
                startNewEntryAfterCreate: false,
                colors: [],
                defaultTagColorID: nil,
                using: repository,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is InlineAnimalWriteProbe.ProbeError)
        }
        XCTAssertEqual(repository.createCount, 1)
    }

    func testInlineEditStillReadsUnderUnchangedSelection() {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = AnimalInlineEntryViewModel()
        let repository = InlineAnimalWriteProbe()
        model.beginNew(selection: selection)
        model.editingAnimalID = UUID()
        model.text = "Daisy"

        XCTAssertThrowsError(
            try model.commit(
                startNewEntryAfterCreate: false,
                colors: [],
                defaultTagColorID: nil,
                using: repository,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is InlineAnimalWriteProbe.ProbeError)
        }
        XCTAssertEqual(repository.fetchCount, 1)
    }

    func testNewDraftAfterHerdSwitchUsesNewSelectionRevision() {
        let originalHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let model = AnimalInlineEntryViewModel()
        let repository = InlineAnimalWriteProbe()
        model.beginNew(selection: selection)
        model.text = "Old Draft"

        selection.select(UUID())
        model.beginNew(selection: selection)
        model.text = "New Draft"

        XCTAssertThrowsError(
            try model.commit(
                startNewEntryAfterCreate: false,
                colors: [],
                defaultTagColorID: nil,
                using: repository,
                selection: selection
            )
        ) { error in
            XCTAssertTrue(error is InlineAnimalWriteProbe.ProbeError)
        }
        XCTAssertEqual(repository.createCount, 1)
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

@MainActor
private enum HerdChange: CaseIterable {
    case switched
    case returned
    case revoked

    func apply(to selection: AppCurrentHerdSelection, originalHerdID: UUID) {
        switch self {
        case .switched:
            selection.select(UUID())
        case .returned:
            selection.select(UUID())
            selection.select(originalHerdID)
        case .revoked:
            selection.select(nil)
        }
    }
}

@MainActor
private final class InlineAnimalWriteProbe: AnimalListRepository {
    enum ProbeError: Error {
        case attempted
    }

    private(set) var createCount = 0
    private(set) var fetchCount = 0
    private(set) var updateCount = 0

    func fetchAnimals() throws -> [AnimalSummary] { [] }

    func fetchAnimalDetail(id: UUID) throws -> AnimalDetailSnapshot? {
        fetchCount += 1
        throw ProbeError.attempted
    }

    func create(input: AnimalInput) throws -> AnimalDetailSnapshot {
        createCount += 1
        throw ProbeError.attempted
    }

    func update(id: UUID, input: AnimalInput) throws -> AnimalDetailSnapshot {
        updateCount += 1
        throw ProbeError.attempted
    }

    func delete(ids: [UUID]) throws {}
    func archive(ids: [UUID]) throws {}
    func restore(ids: [UUID]) throws {}
    func move(ids: [UUID], toPastureID: UUID?) throws {}
}
