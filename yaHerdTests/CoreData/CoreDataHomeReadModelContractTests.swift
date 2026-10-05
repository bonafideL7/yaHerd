import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataHomeReadModelContractTests: XCTestCase {
    func testFieldCheckStatePropagatesToCoreDataHomeReadModel() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        try await HomeSupportingReadModelContract.assertFieldCheckStatePropagatesToHomeReadModel(
            using: environment.fixture
        )
    }

    func testTreatmentTemplatesPropagateToCoreDataHomeReadModel() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        try await HomeSupportingReadModelContract.assertTreatmentTemplatesPropagateToHomeReadModel(
            using: environment.fixture
        )
    }
}

@MainActor
private final class CoreDataHomeReadModelContractEnvironment {
    let assembly: CoreDataPersistenceAssembly
    let selection = CoreDataHomeReadModelContractSelection()
    let herdID = UUID()
    private let temporaryStoreDirectory: URL

    static func make() async throws -> CoreDataHomeReadModelContractEnvironment {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("yaHerd-M9-Home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let storeURL = directory.appendingPathComponent(
            CoreDataPersistentContainer.storeFileName
        )

        do {
            let assembly = try await CoreDataPersistenceAssembly.load(
                storeURL: storeURL
            )
            return try CoreDataHomeReadModelContractEnvironment(
                assembly: assembly,
                temporaryStoreDirectory: directory
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    init(
        assembly: CoreDataPersistenceAssembly,
        temporaryStoreDirectory: URL
    ) throws {
        self.assembly = assembly
        self.temporaryStoreDirectory = temporaryStoreDirectory
        selection.currentHerdID = herdID
        try seedHerd()
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryStoreDirectory)
    }

    var fixture: HomeSupportingReadModelContractFixture {
        HomeSupportingReadModelContractFixture(
            makeFieldCheckRepository: {
                CoreDataFieldCheckRepository(
                    selection: self.selection,
                    assembly: self.assembly
                )
            },
            makeAnimalRepository: {
                CoreDataAnimalRepository(
                    selection: self.selection,
                    assembly: self.assembly
                )
            },
            makePastureCreator: {
                CoreDataPastureRepository(
                    selection: self.selection,
                    assembly: self.assembly
                )
            },
            makeWorkingTemplateRepository: {
                CoreDataWorkingTreatmentTemplateRepository(
                    selection: self.selection,
                    assembly: self.assembly
                )
            },
            makeHomeFieldCheckQueryReader: {
                CoreDataReadModelActor(
                    assembly: self.assembly,
                    currentHerdID: { self.selection.currentHerdID }
                )
            },
            makeHomeWorkingQueryReader: {
                CoreDataReadModelActor(
                    assembly: self.assembly,
                    currentHerdID: { self.selection.currentHerdID }
                )
            }
        )
    }

    private func seedHerd() throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = CDHerd(context: context)
            herd.id = herdID
            herd.name = "M9 Home Contract Herd"
            herd.createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
            herd.updatedAt = herd.createdAt
            try context.save()
        }
    }
}

@MainActor
private final class CoreDataHomeReadModelContractSelection:
    CurrentHerdSelectionReading
{
    var currentHerdID: UUID?
}

extension CoreDataWorkingTreatmentTemplateRepository:
    HomeWorkingTreatmentTemplateContractRepository
{}
