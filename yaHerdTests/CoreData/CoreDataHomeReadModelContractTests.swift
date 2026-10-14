import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataHomeReadModelContractTests: XCTestCase {
    func testCoreDataGrazingCommandRefreshesDashboardAndPreservesOtherPastures() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        let pastures = CoreDataPastureRepository(
            selection: environment.selection,
            assembly: environment.assembly
        )
        let grazed = try pastures.create(
            input: PastureInput(
                name: "Grazed Pasture",
                acreage: 30,
                usableAcreage: 28,
                targetAcresPerHead: 2
            )
        )
        let control = try pastures.create(
            input: PastureInput(
                name: "Untouched Pasture",
                acreage: 24,
                usableAcreage: 22,
                targetAcresPerHead: 2
            )
        )
        let beforeControl = try XCTUnwrap(
            pastures.fetchPastureDetail(id: control.id)
        )
        let readModel = CoreDataReadModelActor(
            contextFactory: environment.assembly.contextFactory,
            lookup: environment.assembly.lookup,
            currentHerdID: { environment.selection.currentHerdID }
        )
        let grazingDate = Date(timeIntervalSinceReferenceDate: 700_000)

        let mutationCenter = ApplicationMutationCenter()
        let marker = MutationPublishingPastureGrazingMarker(
            base: pastures,
            mutationRecorder: ApplicationMutationPipeline(center: mutationCenter),
            writePolicy: LocalDataWritePolicy(dataAccessMode: .readWrite)
        )
        let priorSequence = mutationCenter.currentSequence
        marker.markPastureGrazedToday(id: grazed.id, on: grazingDate)

        XCTAssertEqual(mutationCenter.currentSequence, priorSequence + 1)
        XCTAssertEqual(mutationCenter.homeRevision, 1)
        XCTAssertEqual(mutationCenter.pastureRevision, 1)
        XCTAssertEqual(mutationCenter.revision(for: .dashboard), 1)
        XCTAssertEqual(
            try pastures.fetchPastureDetail(id: grazed.id)?.lastGrazedDate,
            grazingDate
        )
        XCTAssertEqual(
            try pastures.fetchPastureDetail(id: control.id),
            beforeControl
        )

        let dashboard = try await readModel.fetchDashboardPastureRecords()
        XCTAssertEqual(
            dashboard.first(where: { $0.id == grazed.id })?.lastGrazedDate,
            grazingDate
        )
        XCTAssertEqual(
            dashboard.first(where: { $0.id == control.id })?.lastGrazedDate,
            beforeControl.lastGrazedDate
        )

        XCTAssertThrowsError(
            try marker.markPastureGrazedToday(id: UUID(), on: Date())
        ) { error in
            XCTAssertEqual(error as? PastureValidationError, .pastureNotFound)
        }
        XCTAssertEqual(
            mutationCenter.currentSequence,
            priorSequence + 1,
            "A failed Core Data grazing mutation must not publish success."
        )
        XCTAssertEqual(
            try pastures.fetchPastureDetail(id: grazed.id)?.lastGrazedDate,
            grazingDate
        )
    }

    func testRecoveryGrazingCommandRejectsWritesWithoutPublishing() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        let pastures = CoreDataPastureRepository(
            selection: environment.selection,
            assembly: environment.assembly
        )
        let pasture = try pastures.create(
            input: PastureInput(
                name: "Read Only Pasture",
                acreage: nil,
                usableAcreage: nil,
                targetAcresPerHead: nil
            )
        )
        let center = ApplicationMutationCenter()
        let marker = MutationPublishingPastureGrazingMarker(
            base: pastures,
            mutationRecorder: ApplicationMutationPipeline(center: center),
            writePolicy: LocalDataWritePolicy(dataAccessMode: .recoveryReadOnly)
        )

        XCTAssertThrowsError(
            try marker.markPastureGrazedToday(id: pasture.id, on: Date())
        )
        XCTAssertEqual(center.currentSequence, 0)
        XCTAssertNil(try pastures.fetchPastureDetail(id: pasture.id)?.lastGrazedDate)
    }

    func testFieldCheckStatePropagatesToCoreDataHomeReadModel() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        try await HomeSupportingReadModelContract.assertFieldCheckStatePropagatesToHomeReadModel(
            using: environment.fixture
        )
    }

    func testHomeFieldCheckReadRejectsDuplicateFindingIDsAcrossSessions() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        let duplicateFindingID = try environment.seedDuplicateUnresolvedFindingIDsAcrossSessions()
        let reader = environment.fixture.makeHomeFieldCheckQueryReader()

        await XCTAssertThrowsErrorAsync(
            try await reader.fetchHomeFieldCheckRecords()
        ) { error in
            XCTAssertEqual(
                error as? CoreDataPersistenceError,
                .duplicateApplicationID(
                    entity: CDFieldCheckFinding.coreDataEntityName,
                    id: duplicateFindingID,
                    herdID: environment.herdID
                )
            )
        }
    }

    func testHomeFieldCheckReadRejectsDuplicateAnimalCheckIDsAcrossWarningSessions() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        let duplicateCheckID = try environment.seedDuplicateAnimalCheckIDsAcrossWarningSessions()
        let reader = environment.fixture.makeHomeFieldCheckQueryReader()

        await XCTAssertThrowsErrorAsync(
            try await reader.fetchHomeFieldCheckRecords()
        ) { error in
            XCTAssertEqual(
                error as? CoreDataPersistenceError,
                .duplicateApplicationID(
                    entity: CDFieldCheckAnimalCheck.coreDataEntityName,
                    id: duplicateCheckID,
                    herdID: environment.herdID
                )
            )
        }
    }

    func testTreatmentTemplatesPropagateToCoreDataHomeReadModel() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        try await HomeSupportingReadModelContract.assertTreatmentTemplatesPropagateToHomeReadModel(
            using: environment.fixture
        )
    }

    func testReopenedSQLiteTemplateReadDoesNotInventMissingTreatmentIdentity() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        let templates = CoreDataWorkingTreatmentTemplateRepository(
            selection: environment.selection,
            assembly: environment.assembly
        )
        let controlItemID = UUID()
        let controlID = try templates.createTemplate(
            name: "Healthy Control",
            items: [WorkingTreatmentPlanItem(id: controlItemID, name: "Control Treatment")]
        )
        let reader = CoreDataReadModelActor(
            contextFactory: environment.assembly.contextFactory,
            lookup: environment.assembly.lookup,
            currentHerdID: { environment.selection.currentHerdID }
        )
        let originalHome = try await reader.fetchHomeTreatmentTemplates(limit: 10)
        XCTAssertEqual(
            originalHome,
            [WorkingTreatmentTemplateSummary(
                id: controlID, name: "Healthy Control", treatmentCount: 1
            )]
        )

        let corruptTemplateID = UUID()
        let invalidPayload = Data(#"[{"name":"Missing Persisted UUID"}]"#.utf8)
        let writeContext = try environment.assembly.contextFactory.makeWriteContext()
        try writeContext.performAndWait {
            let herd = try XCTUnwrap(
                environment.assembly.lookup.herd(
                    id: environment.herdID,
                    in: writeContext
                )
            )
            let corruptTemplate = CDWorkingTreatmentTemplate(context: writeContext)
            corruptTemplate.id = corruptTemplateID
            corruptTemplate.name = "Invalid Persisted Template"
            corruptTemplate.itemsData = invalidPayload
            corruptTemplate.herd = herd
            try writeContext.save()
        }

        let reopened = try await environment.makeReadOnlyAssembly()
        let reopenedTemplates = CoreDataWorkingTreatmentTemplateRepository(
            selection: environment.selection,
            assembly: reopened
        )
        let control = try XCTUnwrap(
            reopenedTemplates.fetchTemplateDetail(id: controlID)
        )
        XCTAssertEqual(control.id, controlID)
        XCTAssertEqual(control.name, "Healthy Control")
        XCTAssertEqual(control.plannedTreatments.map(\.id), [controlItemID])
        XCTAssertEqual(control.plannedTreatments.map(\.name), ["Control Treatment"])

        let expectedError = CoreDataWorkingMappingError.corruptTreatmentTemplate(
            templateID: corruptTemplateID
        )
        XCTAssertThrowsError(
            try reopenedTemplates.fetchTemplateDetail(id: corruptTemplateID)
        ) { error in
            XCTAssertEqual(error as? CoreDataWorkingMappingError, expectedError)
        }
        XCTAssertThrowsError(try reopenedTemplates.fetchTemplates()) { error in
            XCTAssertEqual(error as? CoreDataWorkingMappingError, expectedError)
        }

        let reopenedHome = CoreDataReadModelActor(
            contextFactory: reopened.contextFactory,
            lookup: reopened.lookup,
            currentHerdID: { environment.selection.currentHerdID }
        )
        await XCTAssertThrowsErrorAsync(
            try await reopenedHome.fetchHomeTreatmentTemplates(limit: 10)
        ) { error in
            XCTAssertEqual(error as? CoreDataWorkingMappingError, expectedError)
        }

        let freshContext = reopened.contextFactory.makeReadContext()
        try freshContext.performAndWait {
            let corrupt = try XCTUnwrap(
                reopened.lookup.herdOwned(
                    CDWorkingTreatmentTemplate.self,
                    id: corruptTemplateID,
                    herdID: environment.herdID,
                    in: freshContext
                )
            )
            XCTAssertEqual(corrupt.itemsData, invalidPayload)
            let healthy = try XCTUnwrap(
                reopened.lookup.herdOwned(
                    CDWorkingTreatmentTemplate.self,
                    id: controlID,
                    herdID: environment.herdID,
                    in: freshContext
                )
            )
            XCTAssertEqual(healthy.name, "Healthy Control")
        }
    }

    func testReopenedSQLiteWorkingTemplateOptionsUsePersistedNameAndUUIDOrder() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        let repository = CoreDataWorkingTreatmentTemplateRepository(
            selection: environment.selection,
            assembly: environment.assembly
        )
        let beforeID = try repository.createTemplate(name: "A First", items: [])
        let afterID = try repository.createTemplate(name: "Z Last", items: [])
        let smallerID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let largerID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000010")
        )
        let context = try environment.assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = try XCTUnwrap(
                environment.assembly.lookup.herd(
                    id: environment.herdID,
                    in: context
                )
            )
            // Persist higher UUID first. The business API rightly rejects
            // duplicate names, but an already persisted store may contain them.
            for id in [largerID, smallerID] {
                let template = CDWorkingTreatmentTemplate(context: context)
                template.id = id
                template.name = "Same Name"
                template.itemsData = Data("[]".utf8)
                template.herd = herd
            }
            try context.save()
        }

        let expected = [
            WorkingTreatmentTemplateSummary(id: beforeID, name: "A First", treatmentCount: 0),
            WorkingTreatmentTemplateSummary(id: smallerID, name: "Same Name", treatmentCount: 0),
            WorkingTreatmentTemplateSummary(id: largerID, name: "Same Name", treatmentCount: 0),
            WorkingTreatmentTemplateSummary(id: afterID, name: "Z Last", treatmentCount: 0)
        ]
        XCTAssertEqual(try repository.fetchTemplates(), expected)
        XCTAssertEqual(try repository.fetchTemplates(), expected)

        let reopened = try await environment.makeReadOnlyAssembly()
        let reopenedTemplates = CoreDataWorkingTreatmentTemplateRepository(
            selection: environment.selection,
            assembly: reopened
        )
        XCTAssertEqual(try reopenedTemplates.fetchTemplates(), expected)
        XCTAssertEqual(
            try reopenedTemplates.fetchTemplateDetail(id: smallerID)?.id,
            smallerID
        )
        let homeReader = CoreDataReadModelActor(
            contextFactory: reopened.contextFactory,
            lookup: reopened.lookup,
            currentHerdID: { environment.selection.currentHerdID }
        )
        XCTAssertEqual(try await homeReader.fetchHomeTreatmentTemplates(limit: 10), expected)
    }

    func testReopenedSQLiteWorkingTemplateLibraryRejectsDuplicateApplicationIDs() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        let repository = CoreDataWorkingTreatmentTemplateRepository(
            selection: environment.selection,
            assembly: environment.assembly
        )
        let controlID = try repository.createTemplate(name: "Unrelated Control", items: [])
        let duplicateID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")
        )
        let context = try environment.assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = try XCTUnwrap(
                environment.assembly.lookup.herd(
                    id: environment.herdID,
                    in: context
                )
            )
            for name in ["Duplicate One", "Duplicate Two"] {
                let template = CDWorkingTreatmentTemplate(context: context)
                template.id = duplicateID
                template.name = name
                template.itemsData = Data("[]".utf8)
                template.herd = herd
            }
            try context.save()
        }

        let expectedError = CoreDataPersistenceError.duplicateApplicationID(
            entity: CDWorkingTreatmentTemplate.coreDataEntityName,
            id: duplicateID,
            herdID: environment.herdID
        )
        XCTAssertThrowsError(try repository.fetchTemplates()) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }

        let reopened = try await environment.makeReadOnlyAssembly()
        let reopenedRepository = CoreDataWorkingTreatmentTemplateRepository(
            selection: environment.selection,
            assembly: reopened
        )
        XCTAssertThrowsError(try reopenedRepository.fetchTemplates()) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }
        let homeReader = CoreDataReadModelActor(
            contextFactory: reopened.contextFactory,
            lookup: reopened.lookup,
            currentHerdID: { environment.selection.currentHerdID }
        )
        await XCTAssertThrowsErrorAsync(
            try await homeReader.fetchHomeTreatmentTemplates(limit: 10)
        ) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }

        // Neither failing reader repairs the malformed store or damages an
        // independently addressable healthy template.
        let control = try XCTUnwrap(
            reopenedRepository.fetchTemplateDetail(id: controlID)
        )
        XCTAssertEqual(control.name, "Unrelated Control")
        XCTAssertEqual(control.plannedTreatments, [])
        let readContext = reopened.contextFactory.makeReadContext()
        try readContext.performAndWait {
            let request = NSFetchRequest<CDWorkingTreatmentTemplate>(
                entityName: CDWorkingTreatmentTemplate.coreDataEntityName
            )
            let allTemplates = try readContext.fetch(request)
            XCTAssertEqual(allTemplates.filter { $0.id == duplicateID }.count, 2)
            XCTAssertEqual(allTemplates.filter { $0.id == controlID }.count, 1)
        }
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

    func makeReadOnlyAssembly() async throws -> CoreDataPersistenceAssembly {
        try await CoreDataPersistenceAssembly.load(
            storeURL: temporaryStoreDirectory.appendingPathComponent(
                CoreDataPersistentContainer.storeFileName
            ),
            accessMode: .readOnly
        )
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
                    contextFactory: self.assembly.contextFactory,
                    lookup: self.assembly.lookup,
                    currentHerdID: { self.selection.currentHerdID }
                )
            },
            makeHomeWorkingQueryReader: {
                CoreDataReadModelActor(
                    contextFactory: self.assembly.contextFactory,
                    lookup: self.assembly.lookup,
                    currentHerdID: { self.selection.currentHerdID }
                )
            }
        )
    }

    func seedDuplicateAnimalCheckIDsAcrossWarningSessions() throws -> UUID {
        let duplicateCheckID = UUID()
        let context = try assembly.contextFactory.makeWriteContext()

        return try context.performAndWait {
            guard let herd = try assembly.lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            for index in 0..<2 {
                let session = CDFieldCheckSession(context: context)
                session.id = UUID()
                session.startedAt = Date(timeIntervalSinceReferenceDate: 9_000 + Double(index))
                session.completedAt = nil
                session.notes = ""
                session.expectedHeadCountSnapshot = 1
                session.quickCowCount = 0
                session.quickHeiferCount = 0
                session.quickCalfCount = 0
                session.quickBullCount = 0
                session.quickSteerCount = 0
                session.pastureIDSnapshot = UUID()
                session.pastureNameSnapshot = "Duplicate Check Pasture \(index)"
                session.pastureArchivedAt = nil
                session.herd = herd

                let check = CDFieldCheckAnimalCheck(context: context)
                check.id = duplicateCheckID
                check.animalIDSnapshot = UUID()
                check.rosterTagNumberSnapshot = "DUP-\(index)"
                check.rosterTagColorIDSnapshot = nil
                check.damRosterTagNumberSnapshot = nil
                check.damRosterTagColorIDSnapshot = nil
                check.animalNameSnapshot = "Duplicate Check Cow \(index)"
                check.animalSexRawValueSnapshot = Sex.female.rawValue
                check.animalTypeRawValueSnapshot = AnimalType.cow.rawValue
                check.wasExpectedAtStart = true
                check.countedAt = nil
                check.missingConfirmedAt = nil
                check.herd = herd
                check.session = session
                check.animal = nil
            }

            try context.save()
            return duplicateCheckID
        }
    }

    func seedDuplicateUnresolvedFindingIDsAcrossSessions() throws -> UUID {
        let duplicateFindingID = UUID()
        let context = try assembly.contextFactory.makeWriteContext()

        return try context.performAndWait {
            guard let herd = try assembly.lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            for index in 0..<2 {
                let session = CDFieldCheckSession(context: context)
                session.id = UUID()
                session.startedAt = Date(timeIntervalSinceReferenceDate: 10_000 + Double(index))
                session.completedAt = nil
                session.notes = ""
                session.expectedHeadCountSnapshot = 0
                session.quickCowCount = 0
                session.quickHeiferCount = 0
                session.quickCalfCount = 0
                session.quickBullCount = 0
                session.quickSteerCount = 0
                session.pastureIDSnapshot = UUID()
                session.pastureNameSnapshot = "Duplicate ID Pasture \(index)"
                session.pastureArchivedAt = nil
                session.herd = herd

                let finding = CDFieldCheckFinding(context: context)
                finding.id = duplicateFindingID
                finding.recordedAt = Date(
                    timeIntervalSinceReferenceDate: 10_100 + Double(index)
                )
                finding.typeRawValue = FieldCheckFindingType.generalObservation.rawValue
                finding.severityRawValue = FieldCheckFindingSeverity.info.rawValue
                finding.statusRawValue = FieldCheckFindingStatus.open.rawValue
                finding.note = "Duplicate unresolved finding"
                finding.animalIDSnapshot = nil
                finding.animalDisplayTagNumberSnapshot = nil
                finding.animalDisplayTagColorIDSnapshot = nil
                finding.animalNameSnapshot = nil
                finding.pastureNameSnapshot = session.pastureNameSnapshot
                finding.herd = herd
                finding.session = session
                finding.animal = nil
            }

            try context.save()
            return duplicateFindingID
        }
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
