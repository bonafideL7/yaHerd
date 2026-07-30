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
        let animalListReadModel = SwiftDataReadModelActor(modelContainer: container)

        let homeSnapshot = try await PerformanceLog.measureAsync("LargeSampleProbe.homeLoading") {
            try await LoadHomeUseCase(
                dashboardReadModel: dashboardReadModel,
                fieldCheckReadModel: fieldCheckReadModel,
                workingReadModel: workingReadModel
            ).execute(configuration: DashboardConfiguration())
        }
        XCTAssertTrue(homeSnapshot.hasPastures)
        XCTAssertTrue(homeSnapshot.hasActiveAnimals)

        let animalListSnapshot = try await animalListReadModel.fetchAnimalListSnapshot(pageSize: 50)
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

        let workingRepository = SwiftDataWorkingRepository(context: context)
        let sessionDetail = try PerformanceLog.measure("LargeSampleProbe.sessionOpening") {
            try workingRepository.fetchSessionDetail(id: workingSession.publicID)
        }
        XCTAssertNotNil(sessionDetail)

        let animalDescriptor = FetchDescriptor<Animal>(
            sortBy: [SortDescriptor(\.tagNumber)]
        )
        let firstAnimal = try XCTUnwrap(context.fetch(animalDescriptor).first)
        let animalRepository = SwiftDataAnimalRepository(context: context)
        let timeline = try PerformanceLog.measure("LargeSampleProbe.timelineRendering") {
            try animalRepository.fetchTimeline(id: firstAnimal.publicID)
        }
        XCTAssertFalse(timeline.isEmpty)
    }
}
