import SwiftData
import XCTest
@testable import yaHerd

@MainActor
final class LargeSamplePersistencePerformanceTests: XCTestCase {
    func testLargeSampleReadOperationsProduceInstrumentableMeasurements() async throws {
        let container = try TestSupport.makeModelContainer()
        let context = container.mainContext
        SampleDataService.seedDefaultsIfNeeded(context: context)
        SampleLargeDataService.seedIfNeeded(context: context)

        let dashboardReadModel = SwiftDataReadModelActor(modelContainer: container)
        let fieldCheckReadModel = SwiftDataReadModelActor(modelContainer: container)
        let workingReadModel = SwiftDataReadModelActor(modelContainer: container)
        let animalReadModel = SwiftDataReadModelActor(modelContainer: container)

        let homeSnapshot = try await PerformanceLog.measureAsync("LargeSampleProbe.homeLoading") {
            try await LoadHomeUseCase(
                dashboardReadModel: dashboardReadModel,
                fieldCheckReadModel: fieldCheckReadModel,
                workingReadModel: workingReadModel
            ).execute(configuration: DashboardConfiguration())
        }
        XCTAssertTrue(homeSnapshot.hasPastures)
        XCTAssertTrue(homeSnapshot.hasActiveAnimals)

        let animalListSnapshot = try await animalReadModel.fetchAnimalListSnapshot(pageSize: 50)
        let formattedTags = Dictionary(
            uniqueKeysWithValues: animalListSnapshot.animals.map { animal in
                (
                    AnimalListTagKey(
                        tagNumber: animal.displayTagNumber,
                        colorID: animal.displayTagColorID
                    ),
                    animal.displayTagNumber
                )
            }
        )
        let derivedState = await PerformanceLog.measureAsync("LargeSampleProbe.animalSearch") {
            await AnimalListDerivationActor().derive(
                AnimalListDerivationRequest(
                    items: animalListSnapshot.animals,
                    searchText: "345",
                    sortOrder: .tagAscending,
                    filter: AnimalFilter(),
                    showRemovedStatuses: true,
                    showArchivedRecords: true,
                    formattedTagsByKey: formattedTags
                )
            )
        }
        XCTAssertTrue(derivedState.filteredAndSortedAnimals.contains { $0.displayTagNumber == "345" })

        let workingSession = WorkingSession(
            date: .now,
            protocolName: "Large sample performance probe",
            protocolItems: []
        )
        context.insertIntoDefaultHerdIfAvailable(workingSession)
        try PersistenceLog.save(context, operation: "LargeSamplePersistencePerformanceTests")
        let workingSessionID = workingSession.publicID

        let sessionDetail = try await PerformanceLog.measureAsync("LargeSampleProbe.sessionOpening") {
            try await workingReadModel.fetchSessionDetail(id: workingSessionID)
        }
        XCTAssertNotNil(sessionDetail)

        let animalDescriptor = FetchDescriptor<Animal>(
            sortBy: [SortDescriptor(\.tagNumber)]
        )
        let firstAnimalID = try XCTUnwrap(context.fetch(animalDescriptor).first).publicID
        let timeline = try await PerformanceLog.measureAsync("LargeSampleProbe.timelineRendering") {
            try await animalReadModel.fetchTimeline(id: firstAnimalID)
        }
        XCTAssertFalse(timeline.isEmpty)
    }
}
