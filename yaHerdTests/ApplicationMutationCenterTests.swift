import XCTest
@testable import yaHerd

@MainActor
final class ApplicationMutationCenterTests: XCTestCase {
    func testAnimalMutationInvalidatesEveryAnimalPresentationArea() {
        let center = ApplicationMutationCenter()

        center.recordSuccessfulMutation(reason: .animal)

        XCTAssertEqual(center.homeRevision, 1)
        XCTAssertEqual(center.animalRevision, 1)
        XCTAssertEqual(center.pastureRevision, 1)
        XCTAssertEqual(center.fieldCheckRevision, 1)
        XCTAssertEqual(center.workingSessionRevision, 1)
        XCTAssertEqual(center.collaborationRevision, 0)
        XCTAssertEqual(
            center.latestEvent?.affectedAreas,
            [.home, .animals, .pastures, .fieldChecks, .workingSessions]
        )
    }

    func testTagColorMutationInvalidatesEmbeddedAnimalRows() {
        let center = ApplicationMutationCenter()

        center.recordSuccessfulMutation(reason: .tagColor)

        XCTAssertEqual(center.animalRevision, 1)
        XCTAssertEqual(center.pastureRevision, 1)
        XCTAssertEqual(center.fieldCheckRevision, 1)
        XCTAssertEqual(center.workingSessionRevision, 1)
        XCTAssertEqual(center.collaborationRevision, 0)
    }

    func testSharedImportIncrementsEveryFeatureRevision() {
        let center = ApplicationMutationCenter()

        center.recordSharedStoreImport()

        XCTAssertEqual(center.homeRevision, 1)
        XCTAssertEqual(center.animalRevision, 1)
        XCTAssertEqual(center.pastureRevision, 1)
        XCTAssertEqual(center.fieldCheckRevision, 1)
        XCTAssertEqual(center.workingSessionRevision, 1)
        XCTAssertEqual(center.collaborationRevision, 1)
        XCTAssertEqual(center.latestEvent?.source, .sharedStoreImport)
        XCTAssertEqual(center.latestEvent?.affectedAreas, Set(ApplicationFeatureArea.allCases))
    }

    func testLateRevisionSubscriberReceivesCurrentRevision() async {
        let center = ApplicationMutationCenter()
        center.recordSuccessfulMutation(reason: .animal)

        var iterator = center.revisions(for: .animals, after: 0).makeAsyncIterator()

        XCTAssertEqual(await iterator.next(), 1)
    }

    func testRevisionStreamBuffersOnlyNewestValue() async {
        let center = ApplicationMutationCenter()
        var iterator = center.revisions(for: .animals, after: 0).makeAsyncIterator()

        center.recordSuccessfulMutation(reason: .animal)
        center.recordSuccessfulMutation(reason: .animal)
        center.recordSuccessfulMutation(reason: .animal)

        XCTAssertEqual(await iterator.next(), 3)
    }

    func testEventStreamCarriesMutationMetadata() async {
        let center = ApplicationMutationCenter()
        var iterator = center.events().makeAsyncIterator()

        center.recordSuccessfulMutation(reason: .animal)
        let event = await iterator.next()

        XCTAssertEqual(event?.source, .local(.animal))
        XCTAssertEqual(event?.sequence, 1)
        XCTAssertEqual(
            event?.affectedAreas,
            [.home, .animals, .pastures, .fieldChecks, .workingSessions]
        )
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
        for _ in 0..<100 {
            if await repository.dashboardFetchCount >= expectedCount {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        let actualCount = await repository.dashboardFetchCount
        XCTAssertEqual(actualCount, expectedCount)
    }
}

private actor RecordingHomeRepository:
    DashboardQueryReading,
    HomeFieldCheckQueryReading,
    HomeWorkingQueryReading
{
    private(set) var dashboardFetchCount = 0

    func fetchDashboardRecords() -> DashboardRecords {
        dashboardFetchCount += 1
        return DashboardRecords(animals: [], pastures: [], workingSessions: [])
    }

    func fetchDashboardAnimalRecords(
        kind: DashboardAnimalListKind
    ) -> [DashboardAnimalRecord] {
        []
    }

    func fetchDashboardPastureRecords() -> [DashboardPastureRecord] {
        []
    }

    func fetchHomeFieldCheckRecords() -> HomeFieldCheckRecords {
        HomeFieldCheckRecords(
            sessions: [],
            openFindings: [],
            openFindingCount: 0,
            hasHistory: false
        )
    }

    func fetchHomeTreatmentTemplates(
        limit: Int
    ) -> [WorkingTreatmentTemplateSummary] {
        []
    }
}
