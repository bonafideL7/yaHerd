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

    static func make() async throws -> CoreDataHomeReadModelContractEnvironment {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        return try CoreDataHomeReadModelContractEnvironment(assembly: assembly)
    }

    init(assembly: CoreDataPersistenceAssembly) throws {
        self.assembly = assembly
        selection.currentHerdID = herdID
        try seedHerd()
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
                    selection: self.selection,
                    assembly: self.assembly
                )
            },
            makeHomeWorkingQueryReader: {
                CoreDataReadModelActor(
                    selection: self.selection,
                    assembly: self.assembly
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
