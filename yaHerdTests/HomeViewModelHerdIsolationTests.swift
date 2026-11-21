import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class HomeViewModelHerdIsolationTests: XCTestCase {
    func testInFlightHomeReadIsRejectedAfterHerdSelectionRoundTrip() async {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let reader = ControlledHomeDashboardReader()
        let model = HomeViewModel()
        let useCase = makeUseCase(reader: reader)

        let firstLoad = Task {
            await model.load(
                configuration: DashboardConfiguration(),
                useCase: useCase,
                selection: selection
            )
        }
        await reader.waitForFirstRead()
        selection.select(UUID())
        selection.select(herdID)
        await reader.completeFirstRead()

        let succeeded = await firstLoad.value
        XCTAssertFalse(succeeded, "Returning to the same UUID does not restore an obsolete read.")
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.hasLoaded)

        let refreshed = await model.load(
            configuration: DashboardConfiguration(),
            useCase: useCase,
            selection: selection
        )
        XCTAssertTrue(refreshed)
        XCTAssertNotNil(model.snapshot)
    }

    func testNewHerdLoadWaitsForOlderInFlightReadInsteadOfStalling() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let reader = ControlledHomeDashboardReader()
        let model = HomeViewModel()
        let useCase = makeUseCase(reader: reader)

        let firstLoad = Task {
            await model.load(
                configuration: DashboardConfiguration(),
                useCase: useCase,
                selection: selection
            )
        }
        await reader.waitForFirstRead()
        selection.select(UUID())

        let nextLoad = Task {
            await model.load(
                configuration: DashboardConfiguration(),
                useCase: useCase,
                selection: selection
            )
        }
        await reader.completeFirstRead()

        let firstSucceeded = await firstLoad.value
        let nextSucceeded = await nextLoad.value
        XCTAssertFalse(firstSucceeded)
        XCTAssertTrue(nextSucceeded, "The new Herd must load even if the old read was still running.")
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNotNil(model.snapshot)
        let fetches = await reader.fetchCount()
        XCTAssertEqual(fetches, 2)
    }

    func testOldMutationObserverCannotReloadAfterHerdSwitch() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let reader = ControlledHomeDashboardReader()
        let model = HomeViewModel()
        let mutationStream = ApplicationMutationCenter()
        let useCase = makeUseCase(reader: reader)

        let oldObserver = Task {
            await model.observe(
                configuration: DashboardConfiguration(),
                useCase: useCase,
                mutationStream: mutationStream,
                selection: selection
            )
        }
        await reader.waitForFirstRead()
        await reader.completeFirstRead()
        for _ in 0..<100 where !model.hasLoaded {
            await Task.yield()
        }
        XCTAssertTrue(model.hasLoaded)

        selection.select(UUID())
        mutationStream.recordSuccessfulMutation(reason: .animal)
        for _ in 0..<30 {
            await Task.yield()
        }
        let obsoleteObserverFetches = await reader.fetchCount()
        XCTAssertEqual(obsoleteObserverFetches, 1, "The obsolete observer cannot read the replacement Herd.")

        oldObserver.cancel()
        _ = await oldObserver.value

        let newObserver = Task {
            await model.observe(
                configuration: DashboardConfiguration(),
                useCase: useCase,
                mutationStream: mutationStream,
                selection: selection
            )
        }
        for _ in 0..<100 {
            if await reader.fetchCount() >= 2 { break }
            await Task.yield()
        }
        let currentObserverFetches = await reader.fetchCount()
        XCTAssertEqual(currentObserverFetches, 2)
        XCTAssertTrue(model.hasLoaded)
        newObserver.cancel()
        _ = await newObserver.value
    }

    private func makeUseCase(reader: ControlledHomeDashboardReader) -> LoadHomeUseCase {
        LoadHomeUseCase(
            dashboardRepository: reader,
            fieldCheckRepository: EmptyHomeFieldCheckReader(),
            workingRepository: EmptyHomeWorkingReader()
        )
    }
}

private actor ControlledHomeDashboardReader: DashboardQueryReading {
    private let records = DashboardRecords(animals: [], pastures: [], workingSessions: [])
    private var fetches = 0
    private var firstRead: CheckedContinuation<DashboardRecords, Error>?
    private var firstReadStarted: CheckedContinuation<Void, Never>?

    func fetchDashboardRecords() async throws -> DashboardRecords {
        fetches += 1
        if fetches == 1 {
            return try await withCheckedThrowingContinuation { continuation in
                firstRead = continuation
                firstReadStarted?.resume()
                firstReadStarted = nil
            }
        }
        return records
    }

    func fetchDashboardAnimalRecords(kind: DashboardAnimalListKind) async throws -> [DashboardAnimalRecord] {
        records.animals
    }

    func fetchDashboardPastureRecords() async throws -> [DashboardPastureRecord] {
        records.pastures
    }

    func waitForFirstRead() async {
        guard firstRead == nil else { return }
        await withCheckedContinuation { continuation in
            firstReadStarted = continuation
        }
    }

    func completeFirstRead() {
        firstRead?.resume(returning: records)
        firstRead = nil
    }

    func fetchCount() -> Int { fetches }
}

private actor EmptyHomeFieldCheckReader: HomeFieldCheckQueryReading {
    func fetchHomeFieldCheckRecords() async throws -> HomeFieldCheckRecords {
        HomeFieldCheckRecords(
            sessions: [],
            openFindings: [],
            openFindingCount: 0,
            hasHistory: false
        )
    }
}

private actor EmptyHomeWorkingReader: HomeWorkingQueryReading {
    func fetchHomeTreatmentTemplates(limit: Int) async throws -> [WorkingTreatmentTemplateSummary] {
        []
    }
}
