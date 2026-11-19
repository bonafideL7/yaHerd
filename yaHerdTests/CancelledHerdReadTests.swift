import Foundation
import XCTest

@testable import yaHerd

@MainActor
final class CancelledHerdReadTests: XCTestCase {
    func testCancelledHomeReadDoesNotPublishLateSuccessAndAllowsRetry() async {
        let reader = SuspendedDashboardReader()
        let model = HomeViewModel()
        let useCase = LoadHomeUseCase(
            dashboardRepository: reader,
            fieldCheckRepository: EmptyHomeFieldCheckReader(),
            workingRepository: EmptyHomeWorkingReader()
        )
        let running = Task { @MainActor in
            await model.load(configuration: DashboardConfiguration(), useCase: useCase)
        }

        await reader.waitUntilStarted()
        running.cancel()
        await reader.releaseFirstRequest()
        let completed = await running.value

        XCTAssertFalse(completed)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.errorMessage)

        let retried = await model.load(configuration: DashboardConfiguration(), useCase: useCase)
        XCTAssertTrue(retried)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNotNil(model.snapshot)
    }

    func testCancelledHomeReadDoesNotPresentLateError() async {
        let reader = SuspendedDashboardReader()
        let model = HomeViewModel()
        let useCase = LoadHomeUseCase(
            dashboardRepository: reader,
            fieldCheckRepository: EmptyHomeFieldCheckReader(),
            workingRepository: EmptyHomeWorkingReader()
        )
        let running = Task { @MainActor in
            await model.load(configuration: DashboardConfiguration(), useCase: useCase)
        }

        await reader.waitUntilStarted()
        running.cancel()
        await reader.failFirstRequest()
        let completed = await running.value

        XCTAssertFalse(completed)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.errorMessage)
    }

    func testCancelledDashboardReadDoesNotPublishLateSuccessAndAllowsRetry() async {
        let reader = SuspendedDashboardReader()
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = DashboardViewModel()
        let running = Task { @MainActor in
            await model.load(configuration: DashboardConfiguration(), using: reader, selection: selection)
        }

        await reader.waitUntilStarted()
        running.cancel()
        await reader.releaseFirstRequest()
        let completed = await running.value

        XCTAssertFalse(completed)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.errorMessage)

        let retried = await model.load(configuration: DashboardConfiguration(), using: reader, selection: selection)
        XCTAssertTrue(retried)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNotNil(model.snapshot)
    }

    func testCancelledDashboardReadDoesNotPresentLateError() async {
        let reader = SuspendedDashboardReader()
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let model = DashboardViewModel()
        let running = Task { @MainActor in
            await model.load(configuration: DashboardConfiguration(), using: reader, selection: selection)
        }

        await reader.waitUntilStarted()
        running.cancel()
        await reader.failFirstRequest()
        let completed = await running.value

        XCTAssertFalse(completed)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.errorMessage)
    }

    func testDashboardLateSuccessIsRejectedAfterHerdSwitch() async {
        let selection = AppCurrentHerdSelection(currentHerdID: UUID())
        let reader = SuspendedDashboardReader()
        let model = DashboardViewModel()
        let running = Task { @MainActor in
            await model.load(configuration: DashboardConfiguration(), using: reader, selection: selection)
        }

        await reader.waitUntilStarted()
        selection.select(UUID())
        await reader.releaseFirstRequest()
        let completed = await running.value

        XCTAssertFalse(completed)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.errorMessage)

        let retried = await model.load(
            configuration: DashboardConfiguration(), using: reader, selection: selection
        )
        XCTAssertTrue(retried)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNotNil(model.snapshot)
    }

    func testDashboardLateSuccessIsRejectedAfterHerdRoundTrip() async {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let reader = SuspendedDashboardReader()
        let model = DashboardViewModel()
        let running = Task { @MainActor in
            await model.load(configuration: DashboardConfiguration(), using: reader, selection: selection)
        }

        await reader.waitUntilStarted()
        selection.select(UUID())
        selection.select(herdID)
        await reader.releaseFirstRequest()
        let completed = await running.value

        XCTAssertFalse(completed)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.snapshot)

        let retried = await model.load(
            configuration: DashboardConfiguration(), using: reader, selection: selection
        )
        XCTAssertTrue(retried)
        XCTAssertTrue(model.hasLoaded)
    }

    func testDashboardLateErrorIsRejectedAfterHerdRoundTrip() async {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let reader = SuspendedDashboardReader()
        let model = DashboardViewModel()
        let running = Task { @MainActor in
            await model.load(configuration: DashboardConfiguration(), using: reader, selection: selection)
        }

        await reader.waitUntilStarted()
        selection.select(UUID())
        selection.select(herdID)
        await reader.failFirstRequest()
        let completed = await running.value

        XCTAssertFalse(completed)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.errorMessage)
    }

    func testCancelledDashboardAnimalListReadDoesNotPublishLateItems() async {
        let reader = SuspendedDashboardReader()
        let model = DashboardAnimalListViewModel()
        let running = Task { @MainActor in
            await model.load(
                kind: .active,
                configuration: DashboardConfiguration(),
                using: reader
            )
        }

        await reader.waitUntilStarted()
        running.cancel()
        await reader.releaseFirstRequest()
        await running.value

        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.errorMessage)

        await model.load(kind: .active, configuration: DashboardConfiguration(), using: reader)
        XCTAssertTrue(model.hasLoaded)
    }

    func testCancelledDashboardPastureListReadDoesNotPublishLateItems() async {
        let reader = SuspendedDashboardReader()
        let model = DashboardPastureListViewModel()
        let running = Task { @MainActor in
            await model.load(configuration: DashboardConfiguration(), using: reader)
        }

        await reader.waitUntilStarted()
        running.cancel()
        await reader.releaseFirstRequest()
        await running.value

        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.errorMessage)

        await model.load(configuration: DashboardConfiguration(), using: reader)
        XCTAssertTrue(model.hasLoaded)
    }
}

private enum SuspendedDashboardReaderError: Error {
    case unavailable
}

/// Deliberately ignores task cancellation, like a slow external or persisted read
/// that finishes after the user switches Herds.
private actor SuspendedDashboardReader: DashboardQueryReading {
    private var didStart = false
    private var shouldSuspend = true
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var pendingDashboard: CheckedContinuation<DashboardRecords, Error>?
    private var pendingAnimals: CheckedContinuation<[DashboardAnimalRecord], Error>?
    private var pendingPastures: CheckedContinuation<[DashboardPastureRecord], Error>?

    func fetchDashboardRecords() async throws -> DashboardRecords {
        guard shouldSuspend else { return emptyRecords }
        return try await withCheckedThrowingContinuation { continuation in
            pendingDashboard = continuation
            markStarted()
        }
    }

    func fetchDashboardAnimalRecords(
        kind _: DashboardAnimalListKind
    ) async throws -> [DashboardAnimalRecord] {
        guard shouldSuspend else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            pendingAnimals = continuation
            markStarted()
        }
    }

    func fetchDashboardPastureRecords() async throws -> [DashboardPastureRecord] {
        guard shouldSuspend else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            pendingPastures = continuation
            markStarted()
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func releaseFirstRequest() {
        shouldSuspend = false
        pendingDashboard?.resume(returning: emptyRecords)
        pendingAnimals?.resume(returning: [])
        pendingPastures?.resume(returning: [])
        clearPendingRequests()
    }

    func failFirstRequest() {
        shouldSuspend = false
        pendingDashboard?.resume(throwing: SuspendedDashboardReaderError.unavailable)
        pendingAnimals?.resume(throwing: SuspendedDashboardReaderError.unavailable)
        pendingPastures?.resume(throwing: SuspendedDashboardReaderError.unavailable)
        clearPendingRequests()
    }

    private var emptyRecords: DashboardRecords {
        DashboardRecords(animals: [], pastures: [], workingSessions: [])
    }

    private func markStarted() {
        didStart = true
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
    }

    private func clearPendingRequests() {
        pendingDashboard = nil
        pendingAnimals = nil
        pendingPastures = nil
    }
}

private struct EmptyHomeFieldCheckReader: HomeFieldCheckQueryReading {
    func fetchHomeFieldCheckRecords() async throws -> HomeFieldCheckRecords {
        HomeFieldCheckRecords(
            sessions: [],
            openFindings: [],
            openFindingCount: 0,
            hasHistory: false
        )
    }
}

private struct EmptyHomeWorkingReader: HomeWorkingQueryReading {
    func fetchHomeTreatmentTemplates(limit _: Int) async throws -> [WorkingTreatmentTemplateSummary] {
        []
    }
}
