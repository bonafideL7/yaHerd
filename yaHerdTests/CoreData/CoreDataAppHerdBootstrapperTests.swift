import CoreData
import XCTest
@testable import yaHerd

final class CoreDataAppHerdBootstrapperTests: XCTestCase {
    func testBootstrapCreatesOneLocalHerdAndReusesItsApplicationID() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

        let createdID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly,
            now: timestamp
        )
        let resolvedID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly,
            now: timestamp.addingTimeInterval(60)
        )

        XCTAssertEqual(resolvedID, createdID)

        let context = assembly.contextFactory.makeReadContext()
        let herds = try context.performAndWait {
            try context.fetch(
                NSFetchRequest<CDHerd>(
                    entityName: CDHerd.coreDataEntityName
                )
            )
        }

        XCTAssertEqual(herds.count, 1)
        XCTAssertEqual(herds.first?.id, createdID)
        XCTAssertEqual(herds.first?.name, CoreDataAppHerdBootstrapper.defaultHerdName)
        XCTAssertEqual(herds.first?.createdAt, timestamp)
        XCTAssertEqual(herds.first?.updatedAt, timestamp)
    }

    func testBootstrapRejectsAmbiguousMultipleHerdRootsAndReportsActualCount() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()

        try await assembly.transactionExecutor.performWrite { context in
            for index in 0..<3 {
                let herd = CDHerd(context: context)
                herd.id = UUID()
                herd.name = "Herd \(index)"
                herd.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
                herd.updatedAt = herd.createdAt
            }
        }

        do {
            _ = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
                assembly: assembly
            )
            XCTFail("Expected multiple-herd bootstrap failure")
        } catch let error as CoreDataAppHerdBootstrapError {
            XCTAssertEqual(error, .multipleLocalHerds(count: 3))
        }
    }

    @MainActor
    func testCoreDataAppGraphSharesHerdStoreMutationsAndReadProjections() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let herdID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly
        )
        let graph = CoreDataAppPersistenceAssembly(
            assembly: assembly,
            currentHerdID: herdID
        ).makeDependencies(dataAccessMode: .readWrite)

        XCTAssertEqual(try graph.herdRepository.fetchCurrentHerd().id, herdID)
        XCTAssertNil(graph.animalFeatureDependencies.sampleDataSeeder)

        let pasture = try graph.pastureFeatureDependencies.createRepository.create(
            input: PastureInput(
                name: "App Graph Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 2
            )
        )
        XCTAssertEqual(
            try graph.pastureFeatureDependencies.listRepository.fetchPastures().map(\.id),
            [pasture.id]
        )
        let dashboardAfterCreate = try await graph.homeFeatureDependencies
            .dashboardQueryReader.fetchDashboardPastureRecords()
        XCTAssertTrue(dashboardAfterCreate.contains { $0.id == pasture.id })
        XCTAssertEqual(graph.applicationMutationCenter.currentSequence, 1)

        try await graph.pastureFeatureDependencies.deletionCommand.deletePastures(
            ids: [pasture.id],
            archivedAt: Date(timeIntervalSinceReferenceDate: 800_000)
        )
        XCTAssertNil(
            try graph.pastureFeatureDependencies.detailRepository.fetchPastureDetail(
                id: pasture.id
            )
        )
        let dashboardAfterDelete = try await graph.homeFeatureDependencies
            .dashboardQueryReader.fetchDashboardPastureRecords()
        XCTAssertFalse(dashboardAfterDelete.contains { $0.id == pasture.id })
        XCTAssertEqual(graph.applicationMutationCenter.currentSequence, 2)
        XCTAssertEqual(graph.applicationMutationCenter.animalRevision, 2)
        XCTAssertEqual(graph.applicationMutationCenter.pastureRevision, 2)
        XCTAssertEqual(graph.applicationMutationCenter.fieldCheckRevision, 2)
    }

    @MainActor
    func testCoreDataAppGraphRecoveryBlocksMutationsWithoutUsingAnotherStore() async throws {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let herdID = try await CoreDataAppHerdBootstrapper.resolveOrCreateCurrentHerdID(
            assembly: assembly
        )
        let graph = CoreDataAppPersistenceAssembly(
            assembly: assembly,
            currentHerdID: herdID
        ).makeDependencies(dataAccessMode: .recoveryReadOnly)

        XCTAssertEqual(try graph.herdRepository.fetchCurrentHerd().id, herdID)
        XCTAssertThrowsError(
            try graph.pastureFeatureDependencies.createRepository.create(
                input: PastureInput(
                    name: "Blocked Pasture",
                    acreage: nil,
                    usableAcreage: nil,
                    targetAcresPerHead: nil
                )
            )
        ) { error in
            XCTAssertTrue(error is LocalDataWritePolicy.WriteError)
        }

        do {
            try await graph.pastureFeatureDependencies.deletionCommand.deletePastures(
                ids: [UUID()],
                archivedAt: Date()
            )
            XCTFail("Expected the recovery policy to reject deletion.")
        } catch {
            XCTAssertTrue(error is LocalDataWritePolicy.WriteError)
        }

        XCTAssertTrue(
            try graph.pastureFeatureDependencies.listRepository.fetchPastures().isEmpty
        )
        XCTAssertEqual(graph.applicationMutationCenter.currentSequence, 0)
    }

    @MainActor
    func testAppCutoverReopensDurableCoreDataHerdAndPastures() async throws {
        let harness = try CoreDataPersistenceHarness()
        let first = try await CoreDataAppPersistenceAssembly.load(
            at: harness.storeURL
        )
        let firstDependencies = first.makeDependencies(dataAccessMode: .readWrite)
        let originalHerdID = try firstDependencies.herdRepository.fetchCurrentHerd().id
        let pasture = try firstDependencies.pastureFeatureDependencies.createRepository.create(
            input: PastureInput(
                name: "Durable Cutover Pasture",
                acreage: 30,
                usableAcreage: 28,
                targetAcresPerHead: 2
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: harness.storeURL.path))

        let reopened = try await CoreDataAppPersistenceAssembly.load(
            at: harness.storeURL
        )
        let reloadedDependencies = reopened.makeDependencies(dataAccessMode: .readWrite)
        XCTAssertEqual(
            try reloadedDependencies.herdRepository.fetchCurrentHerd().id,
            originalHerdID
        )
        XCTAssertEqual(
            try reloadedDependencies.pastureFeatureDependencies.listRepository
                .fetchPastures().map(\\.id),
            [pasture.id]
        )
        let dashboard = try await reloadedDependencies.homeFeatureDependencies
            .dashboardQueryReader.fetchDashboardPastureRecords()
        XCTAssertTrue(dashboard.contains { $0.id == pasture.id })
        XCTAssertEqual(reloadedDependencies.applicationMutationCenter.currentSequence, 0)
    }

    @MainActor
    func testAppCutoverRecoveryUsesOnlyInMemoryCoreDataWithReadOnlyPolicy() async throws {
        let harness = try CoreDataPersistenceHarness()
        let recovery = try await CoreDataAppPersistenceAssembly.inMemoryRecovery()
        let dependencies = recovery.makeDependencies(dataAccessMode: .recoveryReadOnly)

        XCTAssertNotNil(try dependencies.herdRepository.fetchCurrentHerd().id)
        XCTAssertNil(dependencies.animalFeatureDependencies.sampleDataSeeder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.storeURL.path))

        XCTAssertThrowsError(
            try dependencies.pastureFeatureDependencies.createRepository.create(
                input: PastureInput(
                    name: "Blocked Recovery Pasture",
                    acreage: nil,
                    usableAcreage: nil,
                    targetAcresPerHead: nil
                )
            )
        ) { error in
            XCTAssertTrue(error is LocalDataWritePolicy.WriteError)
        }

        do {
            try await dependencies.pastureFeatureDependencies.deletionCommand
                .deletePastures(ids: [UUID()], archivedAt: .now)
            XCTFail("Expected in-memory recovery deletion to be rejected.")
        } catch {
            XCTAssertTrue(error is LocalDataWritePolicy.WriteError)
        }

        XCTAssertTrue(
            try dependencies.pastureFeatureDependencies.listRepository
                .fetchPastures().isEmpty
        )
        XCTAssertEqual(dependencies.applicationMutationCenter.currentSequence, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.storeURL.path))
    }

    @MainActor
    func testAppCurrentHerdSelectionExposesOnlyTheSelectedApplicationID() {
        let firstID = UUID()
        let secondID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: firstID)

        XCTAssertEqual(selection.currentHerdID, firstID)

        selection.select(secondID)
        XCTAssertEqual(selection.currentHerdID, secondID)

        selection.select(nil)
        XCTAssertNil(selection.currentHerdID)
    }
}
