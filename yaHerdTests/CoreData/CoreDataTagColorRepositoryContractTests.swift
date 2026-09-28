@preconcurrency import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataTagColorRepositoryContractTests: XCTestCase {
    func testBuiltInLibraryHasStableIdentityOrderingAndWhiteDefault() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertBuiltInLibraryHasStableIdentityOrderingAndWhiteDefault(
            using: harness.fixture
        )
    }

    func testUpsertNormalizesPersistsAndPreservesApplicationIdentity() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertUpsertNormalizesPersistsAndPreservesApplicationIdentity(
            using: harness.fixture
        )
    }

    func testEmptyNameUpsertIsNoOp() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertEmptyNameUpsertIsNoOp(using: harness.fixture)
    }

    func testDefaultSelectionIsExclusivePersistentAndUnaffectedByUnknownIDs() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertDefaultSelectionIsExclusivePersistentAndUnaffectedByUnknownIDs(
            using: harness.fixture
        )
    }

    func testDeleteRemovesCustomColorsButBuiltInsRemainAvailableAndDefaultFallsBackToWhite() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertDeleteRemovesCustomColorsButBuiltInsRemainAvailableAndDefaultFallsBackToWhite(
            using: harness.fixture
        )
    }

    func testReorderPersistsCompleteLibraryOrder() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertReorderPersistsCompleteLibraryOrder(using: harness.fixture)
    }

    func testRestoreDefaultsRepairsCanonicalDefinitionsPreservesCustomsAndIsIdempotent() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertRestoreDefaultsRepairsCanonicalDefinitionsPreservesCustomsAndIsIdempotent(
            using: harness.fixture
        )
    }

    func testNormalizedNameCollisionKeepsCanonicalIdentityAndRemapsReferences() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertNormalizedNameCollisionKeepsCanonicalIdentityAndRemapsReferences(
            using: harness.fixture
        )
    }

    func testBuiltInNameCollisionPreservesBuiltInIdentityAndRemapsReferences() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertBuiltInNameCollisionPreservesBuiltInIdentityAndRemapsReferences(
            using: harness.fixture
        )
    }

    func testCrossBuiltInNameCollisionPreservesBothStableIdentitiesAndReferences() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertCrossBuiltInNameCollisionPreservesBothStableIdentitiesAndReferences(
            using: harness.fixture
        )
    }

    func testEditingVirtualBuiltInPreservesStableIdentityWhenNameChanges() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertEditingVirtualBuiltInPreservesStableIdentityWhenNameChanges(
            using: harness.fixture
        )
    }

    func testReferencedBuiltInRemovalPreservesReferenceIdentityAndRestoresCanonicalDefinition() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertReferencedBuiltInRemovalPreservesReferenceIdentityAndRestoresCanonicalDefinition(
            using: harness.fixture
        )
    }

    func testReferencedCustomColorRemovalPreservesHistoricalReferenceIdentity() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertReferencedCustomColorRemovalPreservesHistoricalReferenceIdentity(
            using: harness.fixture
        )
    }

    func testReadsWritesDefaultsAndNameUniquenessAreHerdScoped() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertReadsWritesDefaultsAndNameUniquenessAreHerdScoped(
            using: harness.fixture
        )
    }

    func testMissingOrStaleCurrentHerdDoesNotFallbackOrBootstrapOnReadOrWrite() async throws {
        let harness = try await makeHarness()
        try await TagColorRepositoryContract.assertMissingOrStaleCurrentHerdDoesNotFallbackOrBootstrapOnReadOrWrite(
            using: harness.fixture
        )
    }

    func testDuplicatePersistedApplicationIDsAreRejected() async throws {
        let harness = try await makeHarness()
        let duplicateID = UUID()
        let first = TagColorSnapshot(
            id: duplicateID,
            name: "Duplicate A",
            prefix: "DA",
            rgba: RGBAColor(r: 0.1, g: 0.2, b: 0.3)
        )
        let second = TagColorSnapshot(
            id: duplicateID,
            name: "Duplicate B",
            prefix: "DB",
            rgba: RGBAColor(r: 0.4, g: 0.5, b: 0.6)
        )

        try harness.fixture.referenceControl.seedPersistedColor(first)
        try harness.fixture.referenceControl.seedPersistedColor(second)

        XCTAssertThrowsError(try harness.fixture.makeTagColorRepository().fetchColors()) { error in
            guard case let CoreDataPersistenceError.duplicateApplicationID(entity, id, herdID) = error else {
                return XCTFail("Expected duplicateApplicationID, got \(error)")
            }
            XCTAssertEqual(entity, CDTagColorDefinition.coreDataEntityName)
            XCTAssertEqual(id, duplicateID)
            XCTAssertNotNil(herdID)
        }
    }

    private func makeHarness() async throws -> TagColorHarness {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        let selection = TagColorCurrentHerdSelection()
        let initialHerdID = UUID()

        try seedHerd(
            id: initialHerdID,
            name: "Tag Color Core Data Contract Herd",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            assembly: assembly
        )
        selection.currentHerdID = initialHerdID

        let herdSelectionControl = HerdRepositorySelectionTestControl(
            seedHerd: { id, name, createdAt, updatedAt in
                try self.seedHerd(
                    id: id,
                    name: name,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    assembly: assembly
                )
            },
            setCurrentHerdID: { id in
                selection.currentHerdID = id
            },
            persistedHerdRowCountsByID: {
                let context = assembly.contextFactory.makeReadContext()
                return try context.performAndWait {
                    let request = NSFetchRequest<CDHerd>(entityName: CDHerd.coreDataEntityName)
                    return try context.fetch(request).reduce(into: [UUID: Int]()) {
                        $0[$1.id, default: 0] += 1
                    }
                }
            }
        )

        let referenceControl = TagColorReferenceTestControl(
            seedPersistedColor: { snapshot in
                try self.seedColor(snapshot, selection: selection, assembly: assembly)
            },
            seedReferences: { colorID in
                try self.seedReferences(colorID: colorID, selection: selection, assembly: assembly)
            },
            fetchReferences: {
                try self.fetchReferences(selection: selection, assembly: assembly)
            }
        )

        return TagColorHarness(
            fixture: TagColorRepositoryContractFixture(
                makeTagColorRepository: {
                    CoreDataTagColorRepository(selection: selection, assembly: assembly)
                },
                referenceControl: referenceControl,
                herdSelectionControl: herdSelectionControl
            )
        )
    }

    private func seedHerd(
        id: UUID,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        assembly: CoreDataPersistenceAssembly
    ) throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = CDHerd(context: context)
            herd.id = id
            herd.name = name
            herd.createdAt = createdAt
            herd.updatedAt = updatedAt
            try context.save()
        }
    }

    private func seedColor(
        _ snapshot: TagColorSnapshot,
        selection: TagColorCurrentHerdSelection,
        assembly: CoreDataPersistenceAssembly
    ) throws {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            guard let herd = try assembly.lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            let color = CDTagColorDefinition(context: context)
            color.id = snapshot.id
            color.name = snapshot.name
            color.prefix = snapshot.prefix
            color.red = snapshot.rgba.r
            color.green = snapshot.rgba.g
            color.blue = snapshot.rgba.b
            color.alpha = snapshot.rgba.a
            color.sortOrder = Int64(snapshot.sortOrder)
            color.isHidden = false
            color.isDefault = snapshot.isDefault
            color.createdAt = snapshot.createdAt
            color.updatedAt = snapshot.updatedAt
            color.herd = herd
            try context.save()
        }
    }

    private func seedReferences(
        colorID: UUID,
        selection: TagColorCurrentHerdSelection,
        assembly: CoreDataPersistenceAssembly
    ) throws {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            guard let herd = try assembly.lookup.herd(id: herdID, in: context),
                  let color = try assembly.lookup.herdOwned(
                    CDTagColorDefinition.self,
                    id: colorID,
                    herdID: herdID,
                    in: context
                  ) else {
                throw HerdRepositoryError.missingHerd
            }

            let animal = CDAnimal(context: context)
            animal.id = UUID()
            animal.editorRevision = UUID()
            animal.name = "Tag Color Reference Animal"
            animal.sexRawValue = Sex.female.rawValue
            animal.birthDate = Date(timeIntervalSince1970: 1_577_836_800)
            animal.statusRawValue = AnimalStatus.active.rawValue
            animal.isArchived = false
            animal.distinguishingFeaturesData = try JSONEncoder().encode([DistinguishingFeature]())
            animal.herd = herd

            let currentTag = CDAnimalTag(context: context)
            currentTag.id = UUID()
            currentTag.number = "CURRENT"
            currentTag.isPrimary = true
            currentTag.isActive = true
            currentTag.assignedAt = Date(timeIntervalSince1970: 1_700_000_000)
            currentTag.herd = herd
            currentTag.animal = animal
            currentTag.color = color

            let historicalTag = CDAnimalTag(context: context)
            historicalTag.id = UUID()
            historicalTag.number = "HISTORICAL"
            historicalTag.isPrimary = false
            historicalTag.isActive = false
            historicalTag.assignedAt = Date(timeIntervalSince1970: 1_690_000_000)
            historicalTag.removedAt = Date(timeIntervalSince1970: 1_700_000_000)
            historicalTag.herd = herd
            historicalTag.animal = animal
            historicalTag.color = color

            let fieldSession = CDFieldCheckSession(context: context)
            fieldSession.id = UUID()
            fieldSession.startedAt = Date(timeIntervalSince1970: 1_710_000_000)
            fieldSession.notes = ""
            fieldSession.expectedHeadCountSnapshot = 1
            fieldSession.quickCowCount = 0
            fieldSession.quickHeiferCount = 0
            fieldSession.quickCalfCount = 0
            fieldSession.quickBullCount = 0
            fieldSession.quickSteerCount = 0
            fieldSession.pastureIDSnapshot = UUID()
            fieldSession.pastureNameSnapshot = "Reference Pasture"
            fieldSession.herd = herd

            let check = CDFieldCheckAnimalCheck(context: context)
            check.id = UUID()
            check.animalIDSnapshot = animal.id
            check.rosterTagNumberSnapshot = "CURRENT"
            check.rosterTagColorIDSnapshot = colorID
            check.damRosterTagNumberSnapshot = "DAM"
            check.damRosterTagColorIDSnapshot = colorID
            check.animalNameSnapshot = animal.name
            check.animalSexRawValueSnapshot = Sex.female.rawValue
            check.animalTypeRawValueSnapshot = AnimalType.cow.rawValue
            check.wasExpectedAtStart = true
            check.herd = herd
            check.session = fieldSession
            check.animal = animal

            let finding = CDFieldCheckFinding(context: context)
            finding.id = UUID()
            finding.recordedAt = Date(timeIntervalSince1970: 1_710_000_100)
            finding.typeRawValue = "other"
            finding.severityRawValue = "low"
            finding.statusRawValue = "open"
            finding.note = ""
            finding.animalIDSnapshot = animal.id
            finding.animalDisplayTagNumberSnapshot = "CURRENT"
            finding.animalDisplayTagColorIDSnapshot = colorID
            finding.animalNameSnapshot = animal.name
            finding.pastureNameSnapshot = "Reference Pasture"
            finding.herd = herd
            finding.session = fieldSession
            finding.animal = animal

            let workingSession = CDWorkingSession(context: context)
            workingSession.id = UUID()
            workingSession.date = Date(timeIntervalSince1970: 1_720_000_000)
            workingSession.statusRawValue = "finished"
            workingSession.treatmentTemplateNameSnapshot = "Reference"
            workingSession.plannedTreatmentsData = try JSONEncoder().encode([WorkingTreatmentPlanItem]())
            workingSession.sourcePastureIDSnapshot = UUID()
            workingSession.sourcePastureNameSnapshot = "Reference Pasture"
            workingSession.herd = herd

            let queueItem = CDWorkingQueueItem(context: context)
            queueItem.id = UUID()
            queueItem.statusRawValue = "done"
            queueItem.animalIDSnapshot = animal.id
            queueItem.animalTagNumberSnapshot = "CURRENT"
            queueItem.animalTagColorIDSnapshot = colorID
            queueItem.animalNameSnapshot = animal.name
            queueItem.animalSexRawValueSnapshot = Sex.female.rawValue
            queueItem.animalDamDisplayTagNumberSnapshot = "DAM"
            queueItem.animalDamDisplayTagColorIDSnapshot = colorID
            queueItem.herd = herd
            queueItem.session = workingSession
            queueItem.animal = animal

            try context.save()
        }
    }

    private func fetchReferences(
        selection: TagColorCurrentHerdSelection,
        assembly: CoreDataPersistenceAssembly
    ) throws -> TagColorReferenceSnapshot {
        guard let herdID = selection.currentHerdID else {
            throw HerdRepositoryError.missingHerd
        }
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let herd = try assembly.lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }

            let tagRequest = NSFetchRequest<CDAnimalTag>(entityName: CDAnimalTag.coreDataEntityName)
            tagRequest.predicate = NSPredicate(format: "herd == %@", herd)
            let tags = try context.fetch(tagRequest)

            let checkRequest = NSFetchRequest<CDFieldCheckAnimalCheck>(
                entityName: CDFieldCheckAnimalCheck.coreDataEntityName
            )
            checkRequest.predicate = NSPredicate(format: "herd == %@", herd)
            let check = try XCTUnwrap(context.fetch(checkRequest).first)

            let findingRequest = NSFetchRequest<CDFieldCheckFinding>(
                entityName: CDFieldCheckFinding.coreDataEntityName
            )
            findingRequest.predicate = NSPredicate(format: "herd == %@", herd)
            let finding = try XCTUnwrap(context.fetch(findingRequest).first)

            let queueRequest = NSFetchRequest<CDWorkingQueueItem>(
                entityName: CDWorkingQueueItem.coreDataEntityName
            )
            queueRequest.predicate = NSPredicate(format: "herd == %@", herd)
            let queue = try XCTUnwrap(context.fetch(queueRequest).first)

            return TagColorReferenceSnapshot(
                animalTagColorID: tags.first { $0.isActive }?.color?.id,
                historicalTagColorID: tags.first { !$0.isActive }?.color?.id,
                fieldCheckRosterTagColorID: check.rosterTagColorIDSnapshot,
                fieldCheckDamRosterTagColorID: check.damRosterTagColorIDSnapshot,
                fieldCheckFindingTagColorIDSnapshot: finding.animalDisplayTagColorIDSnapshot,
                workingQueueTagColorIDSnapshot: queue.animalTagColorIDSnapshot,
                workingQueueDamTagColorIDSnapshot: queue.animalDamDisplayTagColorIDSnapshot
            )
        }
    }
}

@MainActor
private final class TagColorCurrentHerdSelection: CurrentHerdSelectionReading {
    var currentHerdID: UUID?
}

@MainActor
private struct TagColorHarness {
    let fixture: TagColorRepositoryContractFixture
}
