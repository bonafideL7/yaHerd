import XCTest
@testable import yaHerd

@MainActor
final class ApplicationMutationCenterTests: XCTestCase {
    func testMutationStreamReplaysEventsPublishedAfterCursor() async {
        let center = ApplicationMutationCenter()
        let cursor = center.currentSequence

        center.recordSuccessfulMutation(reason: .animal)

        var iterator = center.events(after: cursor).makeAsyncIterator()
        let event = await iterator.next()

        XCTAssertEqual(event?.source, .local(.animal))
        XCTAssertEqual(event?.sequence, 1)
        XCTAssertTrue(event?.affectedAreas.contains(.home) == true)
        XCTAssertTrue(event?.affectedAreas.contains(.animals) == true)
        XCTAssertTrue(event?.affectedAreas.contains(.dashboard) == true)
    }

    func testSharedImportInvalidatesEveryFeatureArea() async {
        let center = ApplicationMutationCenter()

        center.recordSharedStoreImport()

        var iterator = center.events(after: 0).makeAsyncIterator()
        let event = await iterator.next()

        XCTAssertEqual(event?.source, .sharedStoreImport)
        XCTAssertEqual(event?.affectedAreas, Set(ApplicationFeatureArea.allCases))
    }

    func testHomeModelReloadsAfterAnimalFieldCheckAndWorkingMutations() async throws {
        let center = ApplicationMutationCenter()
        let repository = RecordingHomeRepository()
        let viewModel = HomeViewModel()
        let useCase = LoadHomeUseCase(
            dashboardRepository: repository,
            fieldCheckRepository: repository,
            workingRepository: repository
        )

        let observationTask = Task { @MainActor in
            await viewModel.observe(
                configuration: DashboardConfiguration(),
                useCase: useCase,
                mutationStream: center
            )
        }
        defer { observationTask.cancel() }

        try await waitForFetchCount(1, repository: repository)

        center.recordSuccessfulMutation(reason: .animal)
        try await waitForFetchCount(2, repository: repository)

        center.recordSuccessfulMutation(reason: .fieldCheck)
        try await waitForFetchCount(3, repository: repository)

        center.recordSuccessfulMutation(reason: .working)
        try await waitForFetchCount(4, repository: repository)

        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertNil(viewModel.errorMessage)
    }

    private func waitForFetchCount(
        _ expectedCount: Int,
        repository: RecordingHomeRepository
    ) async throws {
        for _ in 0..<100 where repository.dashboardFetchCount < expectedCount {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(repository.dashboardFetchCount, expectedCount)
    }
}

@MainActor
private final class RecordingHomeRepository:
    DashboardRecordReading,
    FieldCheckOverviewReading,
    WorkingProtocolTemplateListReader
{
    private(set) var dashboardFetchCount = 0

    func fetchDashboardRecords() throws -> DashboardRecords {
        dashboardFetchCount += 1
        return DashboardRecords(animals: [], pastures: [], workingSessions: [])
    }

    func fetchSessions() throws -> [FieldCheckSessionSummary] {
        []
    }

    func fetchOpenFindings(limit: Int) throws -> [FieldCheckFindingSnapshot] {
        []
    }

    func fetchTemplates() throws -> [WorkingProtocolTemplateSummary] {
        []
    }
}
