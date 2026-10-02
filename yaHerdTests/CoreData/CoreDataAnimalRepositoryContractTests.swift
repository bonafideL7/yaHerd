@preconcurrency import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataAnimalRepositoryContractTests: XCTestCase {
    func testCreateUpdateAndReload() async throws {
        let environment = try await makeEnvironment()
        try AnimalRepositoryContract.assertCreateUpdateAndReload(using: environment.repositoryFixture)
    }

    func testArchiveRestorePreservesHistory() async throws {
        let environment = try await makeEnvironment()
        try AnimalRepositoryContract.assertArchiveRestorePreservesHistory(using: environment.repositoryFixture)
    }

    func testMovementUpdatesPastureAndTimeline() async throws {
        let environment = try await makeEnvironment()
        try AnimalRepositoryContract.assertMovementUpdatesPastureAndTimeline(using: environment.repositoryFixture)
    }

    func testTagLifecyclePreservesHistory() async throws {
        let environment = try await makeEnvironment()
        try AnimalRepositoryContract.assertTagLifecyclePreservesHistory(using: environment.repositoryFixture)
    }

    func testParentRelationshipsSurviveReload() async throws {
        let environment = try await makeEnvironment()
        try AnimalRepositoryContract.assertParentRelationshipsSurviveReload(using: environment.repositoryFixture)
    }

    func testHealthAndPregnancyRecordsSurviveReload() async throws {
        let environment = try await makeEnvironment()
        try AnimalRepositoryContract.assertHealthAndPregnancyRecordsSurviveReload(using: environment.repositoryFixture)
    }

    func testDeleteRemovesAggregate() async throws {
        let environment = try await makeEnvironment()
        try AnimalRepositoryContract.assertDeleteRemovesAggregate(using: environment.repositoryFixture)
    }

    func testMilestone5AnimalAggregateTransactionContract() async throws {
        let taggedEnvironment = try await makeEnvironment()
        let untaggedEnvironment = try await makeEnvironment()
        let updateEnvironment = try await makeEnvironment()
        let moveEnvironment = try await makeEnvironment()
        let retagEnvironment = try await makeEnvironment()
        let metadataEnvironment = try await makeEnvironment()
        let retirementEnvironment = try await makeEnvironment()
        let preservationEnvironment = try await makeEnvironment()
        let invalidEnvironment = try await makeEnvironment()

        let fixture = AnimalAggregateTransactionContractFixture(
            makeTaggedCreateProbe: { try taggedEnvironment.makeTaggedCreateProbe() },
            makeUntaggedCreateProbe: { try untaggedEnvironment.makeUntaggedCreateProbe() },
            makeUpdateProbe: { try updateEnvironment.makeCompleteUpdateProbe() },
            makeActivePastureMoveProbe: { try moveEnvironment.makeActivePastureMoveProbe() },
            makeDamRetagProbe: { try retagEnvironment.makeDamRetagProbe() },
            makeSameStatusMetadataProbe: { try metadataEnvironment.makeSameStatusMetadataProbe() },
            makeAllTagsRetiredUpdateProbe: { try retirementEnvironment.makeAllTagsRetiredProbe() },
            makeNonOwnedStatePreservationProbe: {
                try preservationEnvironment.makeNonOwnedStatePreservationProbe()
            },
            makeInvalidTagProbe: { expected, method in
                try invalidEnvironment.makeInvalidTagProbe(expected: expected, method: method)
            }
        )

        try await AnimalAggregateTransactionContract
            .assertTaggedAndUntaggedCreatePersistCompleteAggregateState(using: fixture)
        try await AnimalAggregateTransactionContract
            .assertCompleteUpdateReconcilesRelationshipsTagsAndHistory(using: fixture)
        try await AnimalAggregateTransactionContract
            .assertActivePastureMoveRepairsSourceAndDestinationProjections(using: fixture)
        try await AnimalAggregateTransactionContract
            .assertDamRetagRefreshesDependentOffspringProjections(using: fixture)
        try await AnimalAggregateTransactionContract
            .assertSameStatusMetadataUpdateDoesNotAppendStatusHistory(using: fixture)
        try await AnimalAggregateTransactionContract
            .assertUpdateCanRetireAllActiveTagsWithoutLosingHistory(using: fixture)
        try await AnimalAggregateTransactionContract
            .assertUpdatePreservesNonEditorOwnedState(using: fixture)
        try await AnimalAggregateTransactionContract
            .assertInvalidCompleteTagStatesAreRejectedWithoutMutation(using: fixture)
    }

    func testConcurrentAggregateWritesSerializeIdentityAndRevisionChecksThroughCommit() async throws {
        let environment = try await makeEnvironment()
        let transaction = environment.makeCreateTransaction(
            name: "Concurrent create",
            tagNumber: "CC-1"
        )
        let firstWriter = environment.makeAnimalRepository()
        let secondWriter = environment.makeAnimalRepository()

        async let firstCreate = concurrentCreateOutcome(
            writer: firstWriter,
            transaction: transaction
        )
        async let secondCreate = concurrentCreateOutcome(
            writer: secondWriter,
            transaction: transaction
        )
        let createOutcomes = await [firstCreate, secondCreate]

        XCTAssertEqual(
            createOutcomes.filter { $0 == .success }.count,
            1,
            "Exactly one overlapping create may commit a supplied Animal application UUID."
        )
        XCTAssertEqual(
            createOutcomes.filter { $0 == .duplicateIdentity }.count,
            1,
            "The serialized follower must re-read committed identity and reject the duplicate create."
        )
        XCTAssertNotNil(
            try environment.makeAnimalRepository().fetchAnimalDetail(id: transaction.animalID)
        )

        let staleBase = try XCTUnwrap(
            environment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: transaction.animalID)
        )
        let firstUpdate = UpdateAnimalAggregateTransaction(
            animalID: staleBase.animal.id,
            expectedRevision: staleBase.revision,
            attributes: environment.attributes(
                from: staleBase.animal,
                name: "Concurrent update A"
            ),
            tags: environment.tags(from: staleBase.animal)
        )
        let secondUpdate = UpdateAnimalAggregateTransaction(
            animalID: staleBase.animal.id,
            expectedRevision: staleBase.revision,
            attributes: environment.attributes(
                from: staleBase.animal,
                name: "Concurrent update B"
            ),
            tags: environment.tags(from: staleBase.animal)
        )

        async let firstResult = concurrentUpdateOutcome(
            writer: environment.makeAnimalRepository(),
            transaction: firstUpdate
        )
        async let secondResult = concurrentUpdateOutcome(
            writer: environment.makeAnimalRepository(),
            transaction: secondUpdate
        )
        let updateOutcomes = await [firstResult, secondResult]

        XCTAssertEqual(
            updateOutcomes.filter { $0 == .success }.count,
            1,
            "Exactly one overlapping update may commit from a shared expected revision."
        )
        XCTAssertEqual(
            updateOutcomes.filter { $0 == .staleRevision }.count,
            1,
            "The serialized follower must re-read the rotated revision and reject the stale update."
        )

        let final = try XCTUnwrap(
            environment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: transaction.animalID)
        )
        XCTAssertNotEqual(final.revision, staleBase.revision)
        XCTAssertTrue(
            ["Concurrent update A", "Concurrent update B"].contains(final.animal.name)
        )

        let directRaceBase = final
        let aggregatePendingDirectUpdate = UpdateAnimalAggregateTransaction(
            animalID: directRaceBase.animal.id,
            expectedRevision: directRaceBase.revision,
            attributes: environment.attributes(
                from: directRaceBase.animal,
                name: "Aggregate pending direct update"
            ),
            tags: environment.tags(from: directRaceBase.animal)
        )
        let directUpdateBarrier = CoreDataAnimalCommitBarrier()
        let pendingDirectUpdateRace = Task { @MainActor in
            try await environment.makeAnimalRepository().updateAnimal(
                aggregatePendingDirectUpdate,
                beforeSave: { _ in
                    directUpdateBarrier.blockUntilReleased()
                }
            )
        }

        await waitUntilReached(directUpdateBarrier)
        XCTAssertTrue(
            directUpdateBarrier.didReach,
            "The aggregate transaction must reach its pre-save boundary before the direct mutation."
        )

        do {
            _ = try environment.makeAnimalRepository().update(
                id: directRaceBase.animal.id,
                input: directInput(
                    from: directRaceBase.animal,
                    name: "Direct update winner"
                )
            )
        } catch {
            directUpdateBarrier.release()
            _ = try? await pendingDirectUpdateRace.value
            throw error
        }
        directUpdateBarrier.release()

        do {
            _ = try await pendingDirectUpdateRace.value
            XCTFail("An aggregate save that loses to a direct revision-changing update must report stale state.")
        } catch let error as AnimalAggregateTransactionError {
            XCTAssertEqual(
                error,
                .staleRevision(animalID: directRaceBase.animal.id)
            )
        }

        let afterDirectWinner = try XCTUnwrap(
            environment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: directRaceBase.animal.id)
        )
        XCTAssertEqual(afterDirectWinner.animal.name, "Direct update winner")
        XCTAssertNotEqual(afterDirectWinner.revision, directRaceBase.revision)

        let deleteTransaction = environment.makeCreateTransaction(
            name: "Concurrent delete subject",
            tagNumber: "CC-DELETE"
        )
        _ = try await environment.makeAnimalRepository().createAnimal(deleteTransaction)
        let deleteRaceBase = try XCTUnwrap(
            environment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: deleteTransaction.animalID)
        )
        let aggregatePendingDelete = UpdateAnimalAggregateTransaction(
            animalID: deleteRaceBase.animal.id,
            expectedRevision: deleteRaceBase.revision,
            attributes: environment.attributes(
                from: deleteRaceBase.animal,
                name: "Aggregate pending delete"
            ),
            tags: environment.tags(from: deleteRaceBase.animal)
        )
        let deleteBarrier = CoreDataAnimalCommitBarrier()
        let pendingDeleteRace = Task { @MainActor in
            try await environment.makeAnimalRepository().updateAnimal(
                aggregatePendingDelete,
                beforeSave: { _ in
                    deleteBarrier.blockUntilReleased()
                }
            )
        }

        await waitUntilReached(deleteBarrier)
        XCTAssertTrue(
            deleteBarrier.didReach,
            "The aggregate transaction must reach its pre-save boundary before hard delete."
        )

        do {
            try environment.makeAnimalRepository().delete(ids: [deleteRaceBase.animal.id])
        } catch {
            deleteBarrier.release()
            _ = try? await pendingDeleteRace.value
            throw error
        }
        deleteBarrier.release()

        do {
            _ = try await pendingDeleteRace.value
            XCTFail("An aggregate save whose target is deleted concurrently must report the missing aggregate.")
        } catch let error as AnimalAggregateTransactionError {
            XCTAssertEqual(
                error,
                .aggregateNotFound(animalID: deleteRaceBase.animal.id)
            )
        }
        XCTAssertNil(
            try environment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: deleteRaceBase.animal.id)
        )

        let noOpRaceBase = try XCTUnwrap(
            environment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: directRaceBase.animal.id)
        )
        let noOpUpdate = UpdateAnimalAggregateTransaction(
            animalID: noOpRaceBase.animal.id,
            expectedRevision: noOpRaceBase.revision,
            attributes: environment.attributes(from: noOpRaceBase.animal),
            tags: environment.tags(from: noOpRaceBase.animal)
        )
        let noOpUpdateBarrier = CoreDataAnimalAsyncCommitBarrier()
        let pendingNoOpUpdate = Task { @MainActor in
            try await environment.makeAnimalRepository().updateAnimal(
                noOpUpdate,
                beforeSave: nil,
                beforeSuccessfulRevalidation: {
                    await noOpUpdateBarrier.waitUntilReleased()
                }
            )
        }

        await waitUntilReached(noOpUpdateBarrier)
        _ = try environment.makeAnimalRepository().update(
            id: noOpRaceBase.animal.id,
            input: directInput(
                from: noOpRaceBase.animal,
                name: "Direct winner over no-op aggregate"
            )
        )
        await noOpUpdateBarrier.release()

        do {
            _ = try await pendingNoOpUpdate.value
            XCTFail("A no-op aggregate that loses to a direct revision-changing update must report stale state.")
        } catch let error as AnimalAggregateTransactionError {
            XCTAssertEqual(
                error,
                .staleRevision(animalID: noOpRaceBase.animal.id)
            )
        }

        let afterNoOpDirectWinner = try XCTUnwrap(
            environment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: noOpRaceBase.animal.id)
        )
        XCTAssertEqual(
            afterNoOpDirectWinner.animal.name,
            "Direct winner over no-op aggregate"
        )
        XCTAssertNotEqual(afterNoOpDirectWinner.revision, noOpRaceBase.revision)

        let noOpDeleteTransaction = environment.makeCreateTransaction(
            name: "No-op delete subject",
            tagNumber: "CC-NOOP-DELETE"
        )
        _ = try await environment.makeAnimalRepository().createAnimal(noOpDeleteTransaction)
        let noOpDeleteBase = try XCTUnwrap(
            environment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: noOpDeleteTransaction.animalID)
        )
        let noOpDeleteUpdate = UpdateAnimalAggregateTransaction(
            animalID: noOpDeleteBase.animal.id,
            expectedRevision: noOpDeleteBase.revision,
            attributes: environment.attributes(from: noOpDeleteBase.animal),
            tags: environment.tags(from: noOpDeleteBase.animal)
        )
        let noOpDeleteBarrier = CoreDataAnimalAsyncCommitBarrier()
        let pendingNoOpDelete = Task { @MainActor in
            try await environment.makeAnimalRepository().updateAnimal(
                noOpDeleteUpdate,
                beforeSave: nil,
                beforeSuccessfulRevalidation: {
                    await noOpDeleteBarrier.waitUntilReleased()
                }
            )
        }

        await waitUntilReached(noOpDeleteBarrier)
        try environment.makeAnimalRepository().delete(ids: [noOpDeleteBase.animal.id])
        await noOpDeleteBarrier.release()

        do {
            _ = try await pendingNoOpDelete.value
            XCTFail("A no-op aggregate whose target is deleted concurrently must report the missing aggregate.")
        } catch let error as AnimalAggregateTransactionError {
            XCTAssertEqual(
                error,
                .aggregateNotFound(animalID: noOpDeleteBase.animal.id)
            )
        }
        XCTAssertNil(
            try environment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: noOpDeleteBase.animal.id)
        )
    }

    func testConcurrentTagColorMaterializationAcrossWritersRejectsDuplicateIdentity() async throws {
        let directEnvironment = try await makeEnvironment()
        let directOwnerTransaction = directEnvironment.makeCreateTransaction(
            name: "Direct color owner",
            tagNumber: "DIRECT-COLOR-OWNER"
        )
        _ = try await directEnvironment.makeAnimalRepository()
            .createAnimal(directOwnerTransaction)

        let aggregateCreate = directEnvironment.makeCreateTransaction(
            name: "Aggregate color collision",
            tagNumber: "AGG-COLOR",
            colorID: TagColorDefaults.yellowID
        )
        let directBarrier = CoreDataAnimalCommitBarrier()
        let pendingAggregateCreate = Task { @MainActor in
            try await directEnvironment.makeAnimalRepository().createAnimal(
                aggregateCreate,
                beforeSave: { _ in
                    directBarrier.blockUntilReleased()
                }
            )
        }

        await waitUntilReached(directBarrier)
        XCTAssertTrue(
            directBarrier.didReach,
            "The aggregate create must reach the pre-save boundary after reserving the built-in color."
        )

        do {
            _ = try directEnvironment.makeAnimalRepository().addTag(
                animalID: directOwnerTransaction.animalID,
                input: AnimalTagInput(
                    number: "DIRECT-YELLOW",
                    colorID: TagColorDefaults.yellowID,
                    isPrimary: true
                )
            )
            XCTFail("A direct tag writer must not materialize a built-in color reserved by the aggregate transaction.")
        } catch let error as CoreDataPersistenceError {
            XCTAssertEqual(
                error,
                .tagColorMaterializationInProgress(
                    id: TagColorDefaults.yellowID,
                    herdID: directEnvironment.herdID
                )
            )
        }

        directBarrier.release()
        let created = try await pendingAggregateCreate.value
        XCTAssertEqual(
            created.animal.activeTags.first(where: \.isPrimary)?.colorID,
            TagColorDefaults.yellowID
        )
        XCTAssertEqual(
            try directEnvironment.tagColorRowCount(id: TagColorDefaults.yellowID),
            1
        )

        _ = try directEnvironment.makeAnimalRepository().addTag(
            animalID: directOwnerTransaction.animalID,
            input: AnimalTagInput(
                number: "DIRECT-YELLOW",
                colorID: TagColorDefaults.yellowID,
                isPrimary: true
            )
        )
        let directOwner = try XCTUnwrap(
            directEnvironment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: directOwnerTransaction.animalID)
        )
        XCTAssertTrue(
            directOwner.animal.activeTags.contains {
                $0.number == "DIRECT-YELLOW" && $0.colorID == TagColorDefaults.yellowID
            }
        )
        XCTAssertEqual(
            try directEnvironment.tagColorRowCount(id: TagColorDefaults.yellowID),
            1
        )

        let tagRepositoryEnvironment = try await makeEnvironment()
        let subjectTransaction = tagRepositoryEnvironment.makeCreateTransaction(
            name: "Tag repo collision subject",
            tagNumber: "TAG-REPO-SUBJECT"
        )
        _ = try await tagRepositoryEnvironment.makeAnimalRepository()
            .createAnimal(subjectTransaction)
        let subjectBefore = try XCTUnwrap(
            tagRepositoryEnvironment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: subjectTransaction.animalID)
        )
        let updateTags = tagRepositoryEnvironment.tags(from: subjectBefore.animal).map {
            AnimalTagTransactionState(
                id: $0.id,
                number: $0.number,
                colorID: TagColorDefaults.redID,
                isPrimary: $0.isPrimary,
                isActive: $0.isActive
            )
        }
        let aggregateUpdate = UpdateAnimalAggregateTransaction(
            animalID: subjectBefore.animal.id,
            expectedRevision: subjectBefore.revision,
            attributes: tagRepositoryEnvironment.attributes(from: subjectBefore.animal),
            tags: updateTags
        )
        let tagRepositoryBarrier = CoreDataAnimalCommitBarrier()
        let pendingAggregateUpdate = Task { @MainActor in
            try await tagRepositoryEnvironment.makeAnimalRepository().updateAnimal(
                aggregateUpdate,
                beforeSave: { _ in
                    tagRepositoryBarrier.blockUntilReleased()
                }
            )
        }

        await waitUntilReached(tagRepositoryBarrier)
        XCTAssertTrue(
            tagRepositoryBarrier.didReach,
            "The aggregate update must reach the pre-save boundary after reserving the built-in color."
        )

        do {
            try tagRepositoryEnvironment.makeTagColorRepository()
                .setDefaultColor(id: TagColorDefaults.redID)
            XCTFail("The Tag Color repository must not materialize a built-in color reserved by the aggregate transaction.")
        } catch let error as CoreDataPersistenceError {
            XCTAssertEqual(
                error,
                .tagColorMaterializationInProgress(
                    id: TagColorDefaults.redID,
                    herdID: tagRepositoryEnvironment.herdID
                )
            )
        }

        tagRepositoryBarrier.release()
        let updated = try await pendingAggregateUpdate.value
        XCTAssertNotEqual(updated.revision, subjectBefore.revision)
        XCTAssertEqual(
            updated.animal.activeTags.first(where: \.isPrimary)?.colorID,
            TagColorDefaults.redID
        )
        XCTAssertEqual(
            try tagRepositoryEnvironment.tagColorRowCount(id: TagColorDefaults.redID),
            1
        )

        try tagRepositoryEnvironment.makeTagColorRepository()
            .setDefaultColor(id: TagColorDefaults.redID)
        XCTAssertEqual(
            try tagRepositoryEnvironment.makeTagColorRepository()
                .fetchColor(id: TagColorDefaults.redID)?.id,
            TagColorDefaults.redID
        )
        XCTAssertEqual(
            try tagRepositoryEnvironment.tagColorRowCount(id: TagColorDefaults.redID),
            1
        )

        let defaultEnvironment = try await makeEnvironment()
        let defaultSubject = defaultEnvironment.makeCreateTransaction(
            name: "Default arbitration subject",
            tagNumber: "DEFAULT-ARBITRATION",
            colorID: TagColorDefaults.redID
        )
        _ = try await defaultEnvironment.makeAnimalRepository().createAnimal(defaultSubject)
        let defaultBefore = try XCTUnwrap(
            defaultEnvironment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: defaultSubject.animalID)
        )
        let defaultTags = defaultEnvironment.tags(from: defaultBefore.animal).map {
            AnimalTagTransactionState(
                id: $0.id,
                number: $0.number,
                colorID: TagColorDefaults.whiteID,
                isPrimary: $0.isPrimary,
                isActive: $0.isActive
            )
        }
        let defaultUpdate = UpdateAnimalAggregateTransaction(
            animalID: defaultBefore.animal.id,
            expectedRevision: defaultBefore.revision,
            attributes: defaultEnvironment.attributes(from: defaultBefore.animal),
            tags: defaultTags
        )
        let defaultBarrier = CoreDataAnimalCommitBarrier()
        let pendingDefaultMaterialization = Task { @MainActor in
            try await defaultEnvironment.makeAnimalRepository().updateAnimal(
                defaultUpdate,
                beforeSave: { _ in
                    defaultBarrier.blockUntilReleased()
                }
            )
        }

        await waitUntilReached(defaultBarrier)
        XCTAssertTrue(
            defaultBarrier.didReach,
            "The aggregate update must reach the pre-save boundary after reserving the Herd default slot."
        )

        do {
            try defaultEnvironment.makeTagColorRepository()
                .setDefaultColor(id: TagColorDefaults.redID)
            XCTFail("A default-color write must not overlap aggregate materialization that owns the Herd default slot.")
        } catch let error as CoreDataPersistenceError {
            XCTAssertEqual(
                error,
                .tagColorDefaultMaterializationInProgress(
                    herdID: defaultEnvironment.herdID
                )
            )
        }

        defaultBarrier.release()
        _ = try await pendingDefaultMaterialization.value
        let visibleDefaults = try defaultEnvironment.makeTagColorRepository()
            .fetchColors()
            .filter(\.isDefault)
        XCTAssertEqual(visibleDefaults.count, 1)
        XCTAssertEqual(visibleDefaults.first?.id, TagColorDefaults.whiteID)

        try defaultEnvironment.makeTagColorRepository()
            .setDefaultColor(id: TagColorDefaults.redID)
        let defaultsAfterRelease = try defaultEnvironment.makeTagColorRepository()
            .fetchColors()
            .filter(\.isDefault)
        XCTAssertEqual(defaultsAfterRelease.count, 1)
        XCTAssertEqual(defaultsAfterRelease.first?.id, TagColorDefaults.redID)
    }

    func testAnimalAggregateRevisionLifecycleAndStaleRejection() async throws {
        let revisionEnvironment = try await makeEnvironment()
        let missingEnvironment = try await makeEnvironment()
        let fixture = AnimalAggregatePreconditionContractFixture(
            makeAnimalAggregateRevisionProbe: {
                try revisionEnvironment.makeRevisionProbe()
            },
            makeAnimalAggregateMissingProbe: {
                try missingEnvironment.makeMissingProbe()
            }
        )

        try await PersistenceTransactionPreconditionContract
            .assertAnimalAggregateRevisionLifecycleAndStaleRejection(using: fixture)
    }

    func testAnimalAggregateMissingUpdateDoesNotRecreateDeletedAnimal() async throws {
        let revisionEnvironment = try await makeEnvironment()
        let missingEnvironment = try await makeEnvironment()
        let fixture = AnimalAggregatePreconditionContractFixture(
            makeAnimalAggregateRevisionProbe: {
                try revisionEnvironment.makeRevisionProbe()
            },
            makeAnimalAggregateMissingProbe: {
                try missingEnvironment.makeMissingProbe()
            }
        )

        try await PersistenceTransactionPreconditionContract
            .assertAnimalAggregateUpdateRejectsDeletedAggregateWithoutRecreation(using: fixture)
    }

    func testAnimalAggregateCreateAndUpdateRollbackAfterStaging() async throws {
        let createEnvironment = try await makeEnvironment()
        let updateEnvironment = try await makeEnvironment()
        let fixture = AnimalAggregateRollbackContractFixture(
            makeAnimalAggregateCreateProbe: {
                try createEnvironment.makeCreateRollbackProbe()
            },
            makeAnimalAggregateUpdateProbe: {
                try updateEnvironment.makeUpdateRollbackProbe()
            }
        )

        try await PersistenceTransactionRollbackContract
            .assertAnimalAggregateTransactionsRollBackAllDurableState(using: fixture)
    }

    func testMilestone6PastureDeletionRejectsStaleExpectedStateBeforeMutation() async throws {
        let revisionEnvironment = try await makeEnvironment()
        let missingAnimalEnvironment = try await makeEnvironment()
        let residentChangedEnvironment = try await makeEnvironment()
        let missingPastureEnvironment = try await makeEnvironment()

        let fixture = PersistenceTransactionPreconditionContractFixture(
            makeAnimalAggregateRevisionProbe: {
                try revisionEnvironment.makeRevisionProbe()
            },
            makeAnimalAggregateMissingProbe: {
                try missingAnimalEnvironment.makeMissingProbe()
            },
            makePastureResidentSetChangedProbe: {
                try residentChangedEnvironment.makePastureResidentSetChangedProbe()
            },
            makePastureMissingProbe: {
                try missingPastureEnvironment.makePastureMissingProbe()
            }
        )

        try await PersistenceTransactionPreconditionContract
            .assertPastureDeletionRejectsStaleExpectedStateBeforeMutation(using: fixture)
    }

    func testMilestone6PastureDeletionRejectsMissingMoveDestinationWithoutMutation() async throws {
        let environment = try await makeEnvironment()
        let pastures = environment.makePastureRepository()
        let source = try pastures.create(
            input: PastureInput(name: "Missing destination source", acreage: 10, usableAcreage: 9, targetAcresPerHead: 1)
        )
        let destination = try pastures.create(
            input: PastureInput(name: "Missing destination", acreage: 11, usableAcreage: 10, targetAcresPerHead: 1)
        )
        let resident = try environment.makeAnimalRepository().create(
            input: environment.contractAnimalInput(
                name: "Destination stale resident",
                tagNumber: "M6-DEST-MISSING",
                pastureID: source.id
            )
        )
        let plan = DeletePasturesTransactionPlan(
            expectedStates: [
                PastureDeletionExpectedState(
                    pastureID: source.id,
                    residentAnimalIDs: [resident.id]
                )
            ],
            operations: [
                .moveAnimals(
                    animalIDs: [resident.id],
                    fromPastureID: source.id,
                    toPastureID: destination.id
                ),
                .archiveFieldChecks(
                    pastureIDs: [source.id],
                    archivedAt: Date(timeIntervalSinceReferenceDate: 96_500)
                ),
                .deletePastures(ids: [source.id])
            ]
        )

        try pastures.delete(ids: [destination.id])
        let baseline = try CoreDataContractStoreSnapshotter.snapshot(assembly: environment.assembly)

        do {
            try await CoreDataPastureDeletionTransactionWriter(
                selection: environment.selection,
                assembly: environment.assembly
            ).deletePastures(plan)
            XCTFail("A deleted move destination must reject the prepared Pasture deletion plan.")
        } catch let error as PastureDeletionTransactionError {
            XCTAssertEqual(error, .destinationPastureMissing(pastureID: destination.id))
        }

        XCTAssertEqual(
            try CoreDataContractStoreSnapshotter.snapshot(assembly: environment.assembly),
            baseline
        )
        XCTAssertEqual(
            try environment.makeAnimalRepository().fetchAnimalDetail(id: resident.id)?.pastureID,
            source.id
        )
        XCTAssertNotNil(try environment.makePastureRepository().fetchPastureDetail(id: source.id))
    }

    func testMilestone6PastureDeletionRejectsMalformedPlansBeforeMutation() async throws {
        let environment = try await makeEnvironment()
        try await PastureDeletionTransactionContract.assertInvalidPlansRejectBeforeMutation(
            using: try environment.makePastureDeletionInvalidPlanProbe()
        )
    }

    func testMilestone6PastureDeletionCommitsCoreOwnedGraphAndHistory() async throws {
        let environment = try await makeEnvironment()
        let pastures = environment.makePastureRepository()
        let source = try pastures.create(
            input: PastureInput(name: "M6 source", acreage: 20, usableAcreage: 18, targetAcresPerHead: 1)
        )
        let nilDestinationSource = try pastures.create(
            input: PastureInput(name: "M6 nil source", acreage: 18, usableAcreage: 17, targetAcresPerHead: 1)
        )
        let destination = try pastures.create(
            input: PastureInput(name: "M6 destination", acreage: 22, usableAcreage: 20, targetAcresPerHead: 1)
        )
        let sharedGroupSurvivor = try pastures.create(
            input: PastureInput(name: "M6 shared survivor", acreage: 15, usableAcreage: 14, targetAcresPerHead: 1)
        )
        let unrelatedPasture = try pastures.create(
            input: PastureInput(name: "M6 unrelated pasture", acreage: 13, usableAcreage: 12, targetAcresPerHead: 1)
        )
        let emptyGroup = try pastures.createGroup(
            input: PastureGroupInput(name: "M6 empty group", grazeDays: 5, restDays: 20)
        )
        let sharedGroup = try pastures.createGroup(
            input: PastureGroupInput(name: "M6 shared group", grazeDays: 4, restDays: 18)
        )
        try pastures.assignPasture(id: source.id, toGroupID: emptyGroup.id)
        try pastures.assignPasture(id: nilDestinationSource.id, toGroupID: sharedGroup.id)
        try pastures.assignPasture(id: sharedGroupSurvivor.id, toGroupID: sharedGroup.id)

        let animals = environment.makeAnimalRepository()
        let active = try animals.create(
            input: environment.contractAnimalInput(
                name: "M6 active",
                tagNumber: "M6-SUCCESS-A",
                pastureID: source.id
            )
        )
        let nilDestinationResident = try animals.create(
            input: environment.contractAnimalInput(
                name: "M6 nil destination resident",
                tagNumber: "M6-SUCCESS-N",
                pastureID: nilDestinationSource.id
            )
        )
        let inactive = try animals.create(
            input: environment.contractAnimalInput(
                name: "M6 inactive",
                tagNumber: "M6-SUCCESS-I",
                pastureID: source.id
            )
        )
        try animals.archive(ids: [inactive.id])
        let unrelated = try animals.create(
            input: environment.contractAnimalInput(
                name: "M6 unrelated",
                tagNumber: "M6-SUCCESS-U",
                pastureID: unrelatedPasture.id
            )
        )

        let activeBefore = try XCTUnwrap(animals.fetchAnimalAggregateForEditing(id: active.id))
        let nilDestinationBefore = try XCTUnwrap(
            animals.fetchAnimalAggregateForEditing(id: nilDestinationResident.id)
        )
        let inactiveBefore = try XCTUnwrap(animals.fetchAnimalAggregateForEditing(id: inactive.id))
        let unrelatedBefore = try XCTUnwrap(animals.fetchAnimalAggregateForEditing(id: unrelated.id))
        let activeTimelineBefore = try animals.fetchTimeline(id: active.id)
        let nilTimelineBefore = try animals.fetchTimeline(id: nilDestinationResident.id)
        let inactiveTimelineBefore = try animals.fetchTimeline(id: inactive.id)

        let sourceFieldCheckID = try environment.seedFieldCheckSession(
            pastureID: source.id,
            pastureName: source.name
        )
        let nilSourceFieldCheckID = try environment.seedFieldCheckSession(
            pastureID: nilDestinationSource.id,
            pastureName: nilDestinationSource.name
        )
        let unrelatedFieldCheckID = try environment.seedFieldCheckSession(
            pastureID: unrelatedPasture.id,
            pastureName: unrelatedPasture.name
        )
        let unrelatedFieldCheckBefore = try environment.fieldCheckArchiveState(id: unrelatedFieldCheckID)

        let archivedAt = Date(timeIntervalSinceReferenceDate: 97_000)
        let plan = DeletePasturesTransactionPlan(
            expectedStates: [
                PastureDeletionExpectedState(
                    pastureID: source.id,
                    residentAnimalIDs: [active.id]
                ),
                PastureDeletionExpectedState(
                    pastureID: nilDestinationSource.id,
                    residentAnimalIDs: [nilDestinationResident.id]
                )
            ],
            operations: [
                .moveAnimals(
                    animalIDs: [active.id],
                    fromPastureID: source.id,
                    toPastureID: destination.id
                ),
                .moveAnimals(
                    animalIDs: [nilDestinationResident.id],
                    fromPastureID: nilDestinationSource.id,
                    toPastureID: nil
                ),
                .archiveFieldChecks(
                    pastureIDs: [source.id, nilDestinationSource.id],
                    archivedAt: archivedAt
                ),
                .deletePastures(ids: [source.id, nilDestinationSource.id])
            ]
        )

        let writer = CoreDataPastureDeletionTransactionWriter(
            selection: environment.selection,
            assembly: environment.assembly
        )
        try await writer.deletePastures(plan)

        XCTAssertEqual(writer.lastExecutedOperations, plan.operations)
        XCTAssertNil(try environment.makePastureRepository().fetchPastureDetail(id: source.id))
        XCTAssertNil(
            try environment.makePastureRepository().fetchPastureDetail(id: nilDestinationSource.id)
        )
        XCTAssertNotNil(try environment.makePastureRepository().fetchPastureDetail(id: destination.id))
        XCTAssertNotNil(
            try environment.makePastureRepository().fetchPastureDetail(id: unrelatedPasture.id)
        )

        let activeAfter = try XCTUnwrap(
            environment.makeAnimalRepository().fetchAnimalAggregateForEditing(id: active.id)
        )
        XCTAssertEqual(activeAfter.animal.pastureID, destination.id)
        XCTAssertNotEqual(activeAfter.revision, activeBefore.revision)
        XCTAssertEqual(
            try environment.makeAnimalRepository().fetchTimeline(id: active.id).count,
            activeTimelineBefore.count + 1
        )

        let nilDestinationAfter = try XCTUnwrap(
            environment.makeAnimalRepository()
                .fetchAnimalAggregateForEditing(id: nilDestinationResident.id)
        )
        XCTAssertNil(nilDestinationAfter.animal.pastureID)
        XCTAssertNotEqual(nilDestinationAfter.revision, nilDestinationBefore.revision)
        XCTAssertEqual(
            try environment.makeAnimalRepository().fetchTimeline(id: nilDestinationResident.id).count,
            nilTimelineBefore.count + 1
        )

        let inactiveAfter = try XCTUnwrap(
            environment.makeAnimalRepository().fetchAnimalAggregateForEditing(id: inactive.id)
        )
        XCTAssertNil(inactiveAfter.animal.pastureID)
        XCTAssertNotEqual(inactiveAfter.revision, inactiveBefore.revision)
        XCTAssertEqual(
            try environment.makeAnimalRepository().fetchTimeline(id: inactive.id),
            inactiveTimelineBefore
        )

        let unrelatedAfter = try XCTUnwrap(
            environment.makeAnimalRepository().fetchAnimalAggregateForEditing(id: unrelated.id)
        )
        XCTAssertEqual(unrelatedAfter, unrelatedBefore)

        let destinationResidents = try environment.makePastureRepository()
            .fetchResidentAnimals(pastureID: destination.id)
        XCTAssertTrue(destinationResidents.contains { $0.id == active.id })

        let emptyGroupAfter = try XCTUnwrap(
            environment.makePastureRepository().fetchPastureGroupDetail(id: emptyGroup.id)
        )
        XCTAssertTrue(emptyGroupAfter.pastures.isEmpty)

        let sharedGroupAfter = try XCTUnwrap(
            environment.makePastureRepository().fetchPastureGroupDetail(id: sharedGroup.id)
        )
        XCTAssertEqual(Set(sharedGroupAfter.pastures.map(\.id)), [sharedGroupSurvivor.id])

        for fieldCheckID in [sourceFieldCheckID, nilSourceFieldCheckID] {
            let fieldCheckState = try environment.fieldCheckArchiveState(id: fieldCheckID)
            XCTAssertEqual(fieldCheckState.pastureArchivedAt, archivedAt)
            XCTAssertNil(fieldCheckState.livePastureID)
        }
        let sourceFieldCheckState = try environment.fieldCheckArchiveState(id: sourceFieldCheckID)
        XCTAssertEqual(sourceFieldCheckState.pastureIDSnapshot, source.id)
        XCTAssertEqual(sourceFieldCheckState.pastureNameSnapshot, source.name)
        let nilSourceFieldCheckState = try environment.fieldCheckArchiveState(id: nilSourceFieldCheckID)
        XCTAssertEqual(nilSourceFieldCheckState.pastureIDSnapshot, nilDestinationSource.id)
        XCTAssertEqual(nilSourceFieldCheckState.pastureNameSnapshot, nilDestinationSource.name)

        XCTAssertEqual(
            try environment.fieldCheckArchiveState(id: unrelatedFieldCheckID),
            unrelatedFieldCheckBefore
        )
    }

    func testMilestone6PastureDeletionWaitsForActiveResidentWriteThenRejectsStalePlan() async throws {
        let environment = try await makeEnvironment()
        let pasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Concurrent deletion target",
                acreage: 14,
                usableAcreage: 13,
                targetAcresPerHead: 1
            )
        )
        let plan = DeletePasturesTransactionPlan(
            expectedStates: [
                PastureDeletionExpectedState(
                    pastureID: pasture.id,
                    residentAnimalIDs: []
                )
            ],
            operations: [
                .archiveFieldChecks(
                    pastureIDs: [pasture.id],
                    archivedAt: Date(timeIntervalSinceReferenceDate: 95_000)
                ),
                .deletePastures(ids: [pasture.id])
            ]
        )
        let residentTransaction = environment.makeCreateTransaction(
            name: "Concurrent resident",
            tagNumber: "M6-RACE",
            pastureID: pasture.id
        )
        let barrier = CoreDataAnimalCommitBarrier()
        let pendingResident = Task { @MainActor in
            try await environment.makeAnimalRepository().createAnimal(
                residentTransaction,
                beforeSave: { _ in
                    barrier.blockUntilReleased()
                }
            )
        }

        await waitUntilReached(barrier)
        XCTAssertTrue(barrier.didReach)

        let pendingDeletion = Task { @MainActor in
            try await CoreDataPastureDeletionTransactionWriter(
                selection: environment.selection,
                assembly: environment.assembly
            ).deletePastures(plan)
        }

        await Task.yield()
        barrier.release()
        let created = try await pendingResident.value

        do {
            try await pendingDeletion.value
            XCTFail("Deletion must revalidate after the already-active resident write commits.")
        } catch let error as PastureDeletionTransactionError {
            XCTAssertEqual(error, .residentSetChanged(pastureID: pasture.id))
        }

        let reloaded = try XCTUnwrap(
            environment.makeAnimalRepository().fetchAnimalDetail(id: created.animal.id)
        )
        XCTAssertEqual(reloaded.pastureID, pasture.id)
        XCTAssertNotNil(
            try environment.makePastureRepository().fetchPastureDetail(id: pasture.id)
        )
    }

    func testMilestone6NewAnimalWriteIsRejectedWhilePastureDeletionOwnsBoundary() async throws {
        let environment = try await makeEnvironment()
        let pasture = try environment.makePastureRepository().create(
            input: PastureInput(
                name: "Deletion write boundary",
                acreage: 7,
                usableAcreage: 6,
                targetAcresPerHead: 1
            )
        )
        let plan = DeletePasturesTransactionPlan(
            expectedStates: [
                PastureDeletionExpectedState(pastureID: pasture.id, residentAnimalIDs: [])
            ],
            operations: [
                .archiveFieldChecks(
                    pastureIDs: [pasture.id],
                    archivedAt: Date(timeIntervalSinceReferenceDate: 95_500)
                ),
                .deletePastures(ids: [pasture.id])
            ]
        )
        let barrier = CoreDataAnimalCommitBarrier()
        let pendingDeletion = Task { @MainActor in
            try await CoreDataPastureDeletionTransactionWriter(
                selection: environment.selection,
                assembly: environment.assembly
            ).deletePastures(
                plan,
                beforeSave: { _ in barrier.blockUntilReleased() }
            )
        }

        await waitUntilReached(barrier)
        XCTAssertTrue(barrier.didReach)

        do {
            _ = try environment.makeAnimalRepository().create(
                input: environment.contractAnimalInput(
                    name: "Blocked resident write",
                    tagNumber: "M6-BLOCKED",
                    pastureID: nil
                )
            )
            XCTFail("A new Animal write must not begin while Pasture deletion owns the resident-write boundary.")
        } catch let error as CoreDataResidentWriteCoordinationError {
            XCTAssertEqual(error, .pastureDeletionInProgress)
        }

        XCTAssertFalse(
            try environment.makeAnimalRepository().fetchAnimals().contains {
                $0.name == "Blocked resident write"
            }
        )

        barrier.release()
        try await pendingDeletion.value
        XCTAssertNil(try environment.makePastureRepository().fetchPastureDetail(id: pasture.id))
    }

    func testMilestone6DirectPastureWriteIsRejectedWhileDeletionOwnsBoundary() async throws {
        let environment = try await makeEnvironment()
        let pastureRepository = environment.makePastureRepository()
        let target = try pastureRepository.create(
            input: PastureInput(name: "Deletion target", acreage: 10, usableAcreage: 9, targetAcresPerHead: 1)
        )
        let unrelated = try pastureRepository.create(
            input: PastureInput(name: "Unrelated pasture", acreage: 12, usableAcreage: 11, targetAcresPerHead: 1)
        )
        let plan = DeletePasturesTransactionPlan(
            expectedStates: [
                PastureDeletionExpectedState(pastureID: target.id, residentAnimalIDs: [])
            ],
            operations: [
                .archiveFieldChecks(
                    pastureIDs: [target.id],
                    archivedAt: Date(timeIntervalSinceReferenceDate: 95_600)
                ),
                .deletePastures(ids: [target.id])
            ]
        )
        let barrier = CoreDataAnimalCommitBarrier()
        let pendingDeletion = Task { @MainActor in
            try await CoreDataPastureDeletionTransactionWriter(
                selection: environment.selection,
                assembly: environment.assembly
            ).deletePastures(
                plan,
                beforeSave: { _ in barrier.blockUntilReleased() }
            )
        }

        await waitUntilReached(barrier)
        XCTAssertTrue(barrier.didReach)

        do {
            _ = try environment.makePastureRepository().update(
                id: unrelated.id,
                input: PastureInput(
                    name: "Racing rename",
                    acreage: unrelated.acreage,
                    usableAcreage: unrelated.usableAcreage,
                    targetAcresPerHead: unrelated.targetAcresPerHead
                )
            )
            XCTFail("A direct Pasture write must not begin while deletion owns the shared write boundary.")
        } catch let error as CoreDataResidentWriteCoordinationError {
            XCTAssertEqual(error, .pastureDeletionInProgress)
        }

        XCTAssertEqual(
            try environment.makePastureRepository().fetchPastureDetail(id: unrelated.id)?.name,
            unrelated.name
        )

        barrier.release()
        try await pendingDeletion.value

        _ = try environment.makePastureRepository().update(
            id: unrelated.id,
            input: PastureInput(
                name: "Rename after deletion",
                acreage: unrelated.acreage,
                usableAcreage: unrelated.usableAcreage,
                targetAcresPerHead: unrelated.targetAcresPerHead
            )
        )
        XCTAssertEqual(
            try environment.makePastureRepository().fetchPastureDetail(id: unrelated.id)?.name,
            "Rename after deletion"
        )
    }

    func testMilestone6FailedDeletionReleasesNextQueuedDeletion() async throws {
        let environment = try await makeEnvironment()
        let pastureRepository = environment.makePastureRepository()
        let failing = try pastureRepository.create(
            input: PastureInput(name: "Failing queued deletion", acreage: 8, usableAcreage: 7, targetAcresPerHead: 1)
        )
        let succeeding = try pastureRepository.create(
            input: PastureInput(name: "Success after failure", acreage: 9, usableAcreage: 8, targetAcresPerHead: 1)
        )
        func plan(_ pastureID: UUID, archivedAt: Date) -> DeletePasturesTransactionPlan {
            DeletePasturesTransactionPlan(
                expectedStates: [
                    PastureDeletionExpectedState(pastureID: pastureID, residentAnimalIDs: [])
                ],
                operations: [
                    .archiveFieldChecks(pastureIDs: [pastureID], archivedAt: archivedAt),
                    .deletePastures(ids: [pastureID])
                ]
            )
        }

        let barrier = CoreDataAnimalCommitBarrier()
        let pendingFailure = Task { @MainActor in
            try await CoreDataPastureDeletionTransactionWriter(
                selection: environment.selection,
                assembly: environment.assembly
            ).deletePastures(
                plan(failing.id, archivedAt: Date(timeIntervalSinceReferenceDate: 95_700)),
                beforeSave: { _ in
                    barrier.blockUntilReleased()
                    throw CoreDataAnimalContractTestError.injectedFailure
                }
            )
        }

        await waitUntilReached(barrier)
        XCTAssertTrue(barrier.didReach)

        let pendingSuccess = Task { @MainActor in
            try await CoreDataPastureDeletionTransactionWriter(
                selection: environment.selection,
                assembly: environment.assembly
            ).deletePastures(
                plan(succeeding.id, archivedAt: Date(timeIntervalSinceReferenceDate: 95_800))
            )
        }

        await Task.yield()
        barrier.release()

        do {
            try await pendingFailure.value
            XCTFail("The first deletion must surface its injected persistence failure.")
        } catch {
            // The injected failure is the expected first-writer result.
        }
        try await pendingSuccess.value

        XCTAssertNotNil(try environment.makePastureRepository().fetchPastureDetail(id: failing.id))
        XCTAssertNil(try environment.makePastureRepository().fetchPastureDetail(id: succeeding.id))
    }

    func testMilestone6OverlappingPastureDeletionsSerializeWithoutCrash() async throws {
        let environment = try await makeEnvironment()
        let pastureRepository = environment.makePastureRepository()
        let first = try pastureRepository.create(
            input: PastureInput(name: "Queued deletion first", acreage: 8, usableAcreage: 7, targetAcresPerHead: 1)
        )
        let second = try pastureRepository.create(
            input: PastureInput(name: "Queued deletion second", acreage: 9, usableAcreage: 8, targetAcresPerHead: 1)
        )
        func plan(_ pastureID: UUID, archivedAt: Date) -> DeletePasturesTransactionPlan {
            DeletePasturesTransactionPlan(
                expectedStates: [
                    PastureDeletionExpectedState(pastureID: pastureID, residentAnimalIDs: [])
                ],
                operations: [
                    .archiveFieldChecks(pastureIDs: [pastureID], archivedAt: archivedAt),
                    .deletePastures(ids: [pastureID])
                ]
            )
        }

        let barrier = CoreDataAnimalCommitBarrier()
        let firstWriter = CoreDataPastureDeletionTransactionWriter(
            selection: environment.selection,
            assembly: environment.assembly
        )
        let pendingFirst = Task { @MainActor in
            try await firstWriter.deletePastures(
                plan(first.id, archivedAt: Date(timeIntervalSinceReferenceDate: 96_000)),
                beforeSave: { _ in barrier.blockUntilReleased() }
            )
        }

        await waitUntilReached(barrier)
        XCTAssertTrue(barrier.didReach)

        let pendingSecond = Task { @MainActor in
            try await CoreDataPastureDeletionTransactionWriter(
                selection: environment.selection,
                assembly: environment.assembly
            ).deletePastures(
                plan(second.id, archivedAt: Date(timeIntervalSinceReferenceDate: 96_100))
            )
        }

        await Task.yield()
        XCTAssertNotNil(try environment.makePastureRepository().fetchPastureDetail(id: second.id))

        barrier.release()
        try await pendingFirst.value
        try await pendingSecond.value

        XCTAssertNil(try environment.makePastureRepository().fetchPastureDetail(id: first.id))
        XCTAssertNil(try environment.makePastureRepository().fetchPastureDetail(id: second.id))
    }

    func testMilestone6PastureDeletionRotatesEveryAffectedAnimalRevision() async throws {
        let environment = try await makeEnvironment()
        let fixture = AnimalAggregateCrossFeatureRevisionContractFixture(
            makeTestControl: { operation in
                guard operation == .pastureDeletionTransaction else {
                    preconditionFailure("M6 owns only the Pasture deletion transaction revision probe.")
                }
                return try environment.makePastureDeletionRevisionControl()
            },
            makeParentDeletionProjectionProbe: {
                preconditionFailure("Not part of the M6 Pasture deletion revision slice.")
            },
            makeLegacyUpdateTagDependentProjectionProbe: {
                preconditionFailure("Not part of the M6 Pasture deletion revision slice.")
            },
            makeDirectTagDependentProjectionProbe: {
                preconditionFailure("Not part of the M6 Pasture deletion revision slice.")
            },
            makeWorkingTagDependentProjectionProbe: {
                preconditionFailure("Not part of the M6 Pasture deletion revision slice.")
            },
            makeTagColorRemapDependentProjectionProbe: {
                preconditionFailure("Not part of the M6 Pasture deletion revision slice.")
            }
        )

        try await AnimalAggregateCrossFeatureRevisionContract
            .assertPastureDeletionTransactionRotatesRevision(using: fixture)
    }

    func testMilestone6PastureDeletionRollsBackAfterStaging() async throws {
        let createEnvironment = try await makeEnvironment()
        let updateEnvironment = try await makeEnvironment()
        let pastureEnvironment = try await makeEnvironment()

        let fixture = PersistenceTransactionRollbackContractFixture(
            makeAnimalAggregateCreateProbe: {
                try createEnvironment.makeCreateRollbackProbe()
            },
            makeAnimalAggregateUpdateProbe: {
                try updateEnvironment.makeUpdateRollbackProbe()
            },
            makePastureDeletionProbe: {
                try pastureEnvironment.makePastureDeletionRollbackProbe()
            }
        )

        try await PersistenceTransactionRollbackContract
            .assertFailedTargetTransactionsRollBackAllDurableState(using: fixture)
    }

    func testAnimalAndAnimalTagApplicationIdentityContract() async throws {
        let animalAssembly = try await CoreDataPersistenceAssembly.inMemory()
        let tagAssembly = try await CoreDataPersistenceAssembly.inMemory()
        let animalScope = try CoreDataAnimalIdentityContractScope(
            kind: .animal,
            assembly: animalAssembly
        )
        let tagScope = try CoreDataAnimalIdentityContractScope(
            kind: .animalTag,
            assembly: tagAssembly
        )

        let fixture = IdentityContractFixture { kind in
            switch kind {
            case .animal:
                return animalScope.makeControl()
            case .animalTag:
                return tagScope.makeControl()
            default:
                preconditionFailure("Milestone 5 only owns Animal and AnimalTag identity execution.")
            }
        }

        try await IdentityContract.assertDuplicateApplicationIDsFailWithoutReplacingMergingOrReminting(
            using: fixture,
            kinds: [.animal, .animalTag]
        )
    }

    private enum ConcurrentWriteOutcome: Equatable, Sendable {
        case success
        case duplicateIdentity
        case staleRevision
        case unexpected
    }

    private func concurrentCreateOutcome(
        writer: any AnimalAggregateTransactionWriting,
        transaction: CreateAnimalAggregateTransaction
    ) async -> ConcurrentWriteOutcome {
        do {
            _ = try await writer.createAnimal(transaction)
            return .success
        } catch let error as CoreDataPersistenceError {
            guard case .duplicateApplicationID = error else {
                return .unexpected
            }
            return .duplicateIdentity
        } catch {
            return .unexpected
        }
    }

    private func concurrentUpdateOutcome(
        writer: any AnimalAggregateTransactionWriting,
        transaction: UpdateAnimalAggregateTransaction
    ) async -> ConcurrentWriteOutcome {
        do {
            _ = try await writer.updateAnimal(transaction)
            return .success
        } catch let error as AnimalAggregateTransactionError {
            guard case .staleRevision = error else {
                return .unexpected
            }
            return .staleRevision
        } catch {
            return .unexpected
        }
    }

    private func waitUntilReached(
        _ barrier: CoreDataAnimalCommitBarrier
    ) async {
        for _ in 0..<10_000 {
            if barrier.didReach {
                return
            }
            await Task.yield()
        }
    }

    private func waitUntilReached(
        _ barrier: CoreDataAnimalAsyncCommitBarrier
    ) async {
        for _ in 0..<10_000 {
            if await barrier.didReach() {
                return
            }
            await Task.yield()
        }
    }

    private func directInput(
        from detail: AnimalDetailSnapshot,
        name: String
    ) -> AnimalInput {
        let primaryTag = detail.activeTags.first(where: \.isPrimary)
        return AnimalInput(
            name: name,
            tagNumber: primaryTag?.number ?? "",
            tagColorID: primaryTag?.colorID,
            sex: detail.sex,
            birthDate: detail.birthDate,
            status: detail.status,
            pastureID: detail.pastureID,
            sireID: detail.sireID,
            damID: detail.damID,
            distinguishingFeatures: detail.distinguishingFeatures,
            saleDate: detail.saleDate,
            salePrice: detail.salePrice,
            reasonSold: detail.reasonSold,
            deathDate: detail.deathDate,
            causeOfDeath: detail.causeOfDeath,
            statusReferenceID: detail.statusReferenceID
        )
    }

    private func makeEnvironment() async throws -> CoreDataAnimalContractEnvironment {
        let assembly = try await CoreDataPersistenceAssembly.inMemory()
        return try CoreDataAnimalContractEnvironment(assembly: assembly)
    }
}

private actor CoreDataAnimalAsyncCommitBarrier {
    private var reached = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func didReach() -> Bool {
        reached
    }

    func waitUntilReleased() async {
        reached = true
        guard !released else {
            return
        }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private final class CoreDataAnimalCommitBarrier: @unchecked Sendable {
    private let condition = NSCondition()
    private var reached = false
    private var released = false

    var didReach: Bool {
        condition.lock()
        defer { condition.unlock() }
        return reached
    }

    func blockUntilReleased() {
        condition.lock()
        reached = true
        condition.broadcast()
        while !released {
            condition.wait()
        }
        condition.unlock()
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}

@MainActor
private final class CoreDataAnimalContractEnvironment {
    let assembly: CoreDataPersistenceAssembly
    let selection = CoreDataAnimalContractSelection()
    let herdID = UUID()

    init(assembly: CoreDataPersistenceAssembly) throws {
        self.assembly = assembly
        selection.currentHerdID = herdID
        try seedHerd()
    }

    var repositoryFixture: AnimalRepositoryContractFixture {
        AnimalRepositoryContractFixture(
            makeAnimalRepository: { self.makeAnimalRepository() },
            makePastureRepository: { self.makePastureRepository() },
            makeStatusReference: { name, baseStatus in
                try self.makeStatusReference(name: name, baseStatus: baseStatus)
            }
        )
    }

    func makeAnimalRepository() -> CoreDataAnimalRepository {
        CoreDataAnimalRepository(selection: selection, assembly: assembly)
    }

    func makePastureRepository() -> CoreDataPastureRepository {
        CoreDataPastureRepository(selection: selection, assembly: assembly)
    }

    func makeTagColorRepository() -> CoreDataTagColorRepository {
        CoreDataTagColorRepository(selection: selection, assembly: assembly)
    }

    func tagColorRowCount(id: UUID) throws -> Int {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDTagColorDefinition>(
                entityName: CDTagColorDefinition.coreDataEntityName
            )
            request.predicate = NSPredicate(
                format: "id == %@ AND herd.id == %@",
                id as NSUUID,
                herdID as NSUUID
            )
            return try context.count(for: request)
        }
    }

    func makeTaggedCreateProbe() throws -> AnimalAggregateTaggedCreateContractProbe {
        let pastureRepository = makePastureRepository()
        let targetPasture = try pastureRepository.create(
            input: PastureInput(
                name: "Tagged Create Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let animalRepository = makeAnimalRepository()
        let parentSire = try animalRepository.create(
            input: animalInput(
                name: "Tagged Parent Sire",
                tagNumber: "TPS",
                sex: .male
            )
        )
        let parentDam = try animalRepository.create(
            input: animalInput(
                name: "Tagged Parent Dam",
                tagNumber: "TPD",
                sex: .female
            )
        )
        _ = try animalRepository.create(
            input: animalInput(
                name: "Tagged Inference Dam",
                tagNumber: "TID",
                sex: .female,
                pastureID: targetPasture.id
            )
        )
        let statusReference = try makeStatusReference(
            name: "Tagged Active",
            baseStatus: .active
        )
        let transaction = CreateAnimalAggregateTransaction(
            animalID: UUID(),
            attributes: AnimalAggregateAttributes(
                name: "Tagged Aggregate Bull",
                sex: .male,
                birthDate: Date(timeIntervalSinceReferenceDate: 40_000),
                status: .active,
                pastureID: targetPasture.id,
                sireID: parentSire.id,
                damID: parentDam.id,
                distinguishingFeatures: [
                    DistinguishingFeature(description: "Tagged create blaze", order: 0)
                ],
                saleDate: nil,
                salePrice: nil,
                reasonSold: nil,
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: statusReference.id
            ),
            tags: [
                AnimalTagTransactionState(
                    id: UUID(),
                    number: "TC-100",
                    colorID: TagColorDefaults.yellowID,
                    isPrimary: true,
                    isActive: true
                )
            ]
        )

        return AnimalAggregateTaggedCreateContractProbe(
            writer: makeAnimalRepository(),
            makeReader: { self.makeAnimalRepository() },
            makeAnimalRepository: { self.makeAnimalRepository() },
            makeAnimalListQueryReader: nil,
            makeDashboardQueryReader: nil,
            makePastureRepository: { self.makePastureRepository() },
            makeWorkingOwnershipControl: { self.makeWorkingOwnershipControl() },
            transaction: transaction
        )
    }

    func makeUntaggedCreateProbe() throws -> AnimalAggregateUntaggedCreateContractProbe {
        let transaction = CreateAnimalAggregateTransaction(
            animalID: UUID(),
            attributes: AnimalAggregateAttributes(
                name: "Untagged Aggregate Cow",
                sex: .female,
                birthDate: Date(timeIntervalSinceReferenceDate: 41_000),
                status: .active,
                pastureID: pastureID,
                sireID: nil,
                damID: nil,
                distinguishingFeatures: [],
                saleDate: nil,
                salePrice: nil,
                reasonSold: nil,
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: nil
            ),
            tags: []
        )

        return AnimalAggregateUntaggedCreateContractProbe(
            writer: makeAnimalRepository(),
            makeReader: { self.makeAnimalRepository() },
            makeAnimalRepository: { self.makeAnimalRepository() },
            makeAnimalListQueryReader: nil,
            makeDashboardQueryReader: nil,
            makeWorkingOwnershipControl: { self.makeWorkingOwnershipControl() },
            transaction: transaction
        )
    }

    func makeCompleteUpdateProbe() throws -> AnimalAggregateUpdateContractProbe {
        let pastureRepository = makePastureRepository()
        let source = try pastureRepository.create(
            input: PastureInput(
                name: "Complete Update Source",
                acreage: 30,
                usableAcreage: 27,
                targetAcresPerHead: 1.5
            )
        )
        let destination = try pastureRepository.create(
            input: PastureInput(
                name: "Complete Update Destination",
                acreage: 35,
                usableAcreage: 32,
                targetAcresPerHead: 1.5
            )
        )
        let repository = makeAnimalRepository()
        let parentSire = try repository.create(
            input: animalInput(
                name: "Complete Parent Sire",
                tagNumber: "CPS",
                sex: .male
            )
        )
        let oldDam = try repository.create(
            input: animalInput(
                name: "Complete Old Dam",
                tagNumber: "COD",
                sex: .female,
                pastureID: source.id
            )
        )
        let newDam = try repository.create(
            input: animalInput(
                name: "Complete New Dam",
                tagNumber: "CND",
                sex: .female,
                pastureID: destination.id
            )
        )
        _ = try repository.create(
            input: animalInput(
                name: "Complete Inference Dam",
                tagNumber: "CID",
                sex: .female,
                pastureID: destination.id
            )
        )
        let soldReference = try makeStatusReference(
            name: "Complete Sold",
            baseStatus: .sold
        )
        let activeReference = try makeStatusReference(
            name: "Complete Active",
            baseStatus: .active
        )
        let subject = try repository.create(
            input: AnimalInput(
                name: "Complete Subject",
                tagNumber: "CU-PRIMARY",
                tagColorID: TagColorDefaults.yellowID,
                sex: .male,
                birthDate: Date(timeIntervalSinceReferenceDate: 42_000),
                status: .sold,
                pastureID: source.id,
                sireID: parentSire.id,
                damID: oldDam.id,
                distinguishingFeatures: [
                    DistinguishingFeature(description: "Complete old mark", order: 0)
                ],
                saleDate: Date(timeIntervalSinceReferenceDate: 43_000),
                salePrice: 1_500,
                reasonSold: "Complete setup",
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: soldReference.id
            )
        )
        let withSecondary = try repository.addTag(
            animalID: subject.id,
            input: AnimalTagInput(
                number: "CU-SECONDARY",
                colorID: TagColorDefaults.whiteID,
                isPrimary: false
            )
        )
        let secondaryID = try XCTUnwrap(
            withSecondary.activeTags.first { !$0.isPrimary }?.id
        )
        let newTagID = UUID()

        return AnimalAggregateUpdateContractProbe(
            writer: makeAnimalRepository(),
            makeReader: { self.makeAnimalRepository() },
            makeAnimalRepository: { self.makeAnimalRepository() },
            makeAnimalListQueryReader: nil,
            makeDashboardQueryReader: nil,
            makePastureRepository: { self.makePastureRepository() },
            animalID: subject.id,
            makeUpdateTransaction: { current in
                let currentTags = self.tags(from: current.animal)
                let desiredTags = currentTags.map { tag -> AnimalTagTransactionState in
                    if tag.id == secondaryID {
                        return AnimalTagTransactionState(
                            id: tag.id,
                            number: "CU-SECONDARY-EDITED",
                            colorID: TagColorDefaults.redID,
                            isPrimary: true,
                            isActive: true
                        )
                    }
                    return AnimalTagTransactionState(
                        id: tag.id,
                        number: tag.number,
                        colorID: tag.colorID,
                        isPrimary: false,
                        isActive: false
                    )
                } + [
                    AnimalTagTransactionState(
                        id: newTagID,
                        number: "CU-NEW",
                        colorID: TagColorDefaults.blueID,
                        isPrimary: false,
                        isActive: true
                    )
                ]

                return UpdateAnimalAggregateTransaction(
                    animalID: current.animal.id,
                    expectedRevision: current.revision,
                    attributes: AnimalAggregateAttributes(
                        name: current.animal.name + " Updated",
                        sex: current.animal.sex,
                        birthDate: current.animal.birthDate,
                        status: .active,
                        pastureID: destination.id,
                        sireID: nil,
                        damID: newDam.id,
                        distinguishingFeatures: [
                            DistinguishingFeature(description: "Complete new mark", order: 0)
                        ],
                        saleDate: nil,
                        salePrice: nil,
                        reasonSold: nil,
                        deathDate: nil,
                        causeOfDeath: nil,
                        statusReferenceID: activeReference.id
                    ),
                    tags: desiredTags
                )
            }
        )
    }

    func makeActivePastureMoveProbe() throws -> AnimalAggregateActivePastureMoveContractProbe {
        let pastureRepository = makePastureRepository()
        let source = try pastureRepository.create(
            input: PastureInput(
                name: "Move Source",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let destination = try pastureRepository.create(
            input: PastureInput(
                name: "Move Destination",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let repository = makeAnimalRepository()
        let subject = try repository.create(
            input: animalInput(
                name: "Move Subject",
                tagNumber: "MOVE-1",
                sex: .female,
                pastureID: source.id
            )
        )

        return AnimalAggregateActivePastureMoveContractProbe(
            writer: makeAnimalRepository(),
            makeReader: { self.makeAnimalRepository() },
            makeAnimalRepository: { self.makeAnimalRepository() },
            makeDashboardQueryReader: nil,
            makePastureRepository: { self.makePastureRepository() },
            animalID: subject.id,
            makeUpdateTransaction: { current in
                var attributes = self.attributes(from: current.animal)
                attributes = AnimalAggregateAttributes(
                    name: attributes.name,
                    sex: attributes.sex,
                    birthDate: attributes.birthDate,
                    status: attributes.status,
                    pastureID: destination.id,
                    sireID: attributes.sireID,
                    damID: attributes.damID,
                    distinguishingFeatures: attributes.distinguishingFeatures,
                    saleDate: attributes.saleDate,
                    salePrice: attributes.salePrice,
                    reasonSold: attributes.reasonSold,
                    deathDate: attributes.deathDate,
                    causeOfDeath: attributes.causeOfDeath,
                    statusReferenceID: attributes.statusReferenceID
                )
                return UpdateAnimalAggregateTransaction(
                    animalID: current.animal.id,
                    expectedRevision: current.revision,
                    attributes: attributes,
                    tags: self.tags(from: current.animal)
                )
            }
        )
    }

    func makeDamRetagProbe() throws -> AnimalAggregateDamRetagContractProbe {
        let repository = makeAnimalRepository()
        let dam = try repository.create(
            input: AnimalInput(
                name: "Retag Dam",
                tagNumber: "DAM-OLD",
                tagColorID: TagColorDefaults.yellowID,
                sex: .female,
                birthDate: Date(timeIntervalSinceReferenceDate: 44_000),
                status: .active,
                pastureID: nil,
                sireID: nil,
                damID: nil,
                distinguishingFeatures: [],
                saleDate: nil,
                salePrice: nil,
                reasonSold: nil,
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: nil
            )
        )
        let offspring = try repository.create(
            input: AnimalInput(
                name: "Retag Offspring",
                tagNumber: "CALF-1",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSinceReferenceDate: 45_000),
                status: .active,
                pastureID: nil,
                sireID: nil,
                damID: dam.id,
                distinguishingFeatures: [],
                saleDate: nil,
                salePrice: nil,
                reasonSold: nil,
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: nil
            )
        )

        return AnimalAggregateDamRetagContractProbe(
            writer: makeAnimalRepository(),
            makeReader: { self.makeAnimalRepository() },
            makeAnimalRepository: { self.makeAnimalRepository() },
            makeAnimalListQueryReader: nil,
            makeDashboardQueryReader: nil,
            damID: dam.id,
            offspringID: offspring.id,
            makeUpdateTransaction: { current in
                let desiredTags = self.tags(from: current.animal).map {
                    AnimalTagTransactionState(
                        id: $0.id,
                        number: $0.isPrimary ? "DAM-NEW" : $0.number,
                        colorID: $0.isPrimary ? TagColorDefaults.whiteID : $0.colorID,
                        isPrimary: $0.isPrimary,
                        isActive: $0.isActive
                    )
                }
                return UpdateAnimalAggregateTransaction(
                    animalID: current.animal.id,
                    expectedRevision: current.revision,
                    attributes: self.attributes(from: current.animal),
                    tags: desiredTags
                )
            }
        )
    }

    func makeSameStatusMetadataProbe() throws -> AnimalAggregateSameStatusMetadataContractProbe {
        let firstReference = try makeStatusReference(
            name: "Dead Initial",
            baseStatus: .dead
        )
        let replacementReference = try makeStatusReference(
            name: "Dead Replacement",
            baseStatus: .dead
        )
        let repository = makeAnimalRepository()
        let subject = try repository.create(
            input: AnimalInput(
                name: "Same Status Subject",
                tagNumber: "DEAD-1",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSinceReferenceDate: 46_000),
                status: .dead,
                pastureID: nil,
                sireID: nil,
                damID: nil,
                distinguishingFeatures: [],
                saleDate: nil,
                salePrice: nil,
                reasonSold: nil,
                deathDate: Date(timeIntervalSinceReferenceDate: 47_000),
                causeOfDeath: "Initial cause",
                statusReferenceID: firstReference.id
            )
        )

        return AnimalAggregateSameStatusMetadataContractProbe(
            writer: makeAnimalRepository(),
            makeReader: { self.makeAnimalRepository() },
            makeAnimalRepository: { self.makeAnimalRepository() },
            makeAnimalListQueryReader: nil,
            makeDashboardQueryReader: nil,
            animalID: subject.id,
            makeUpdateTransaction: { current in
                let base = self.attributes(from: current.animal)
                return UpdateAnimalAggregateTransaction(
                    animalID: current.animal.id,
                    expectedRevision: current.revision,
                    attributes: AnimalAggregateAttributes(
                        name: base.name,
                        sex: base.sex,
                        birthDate: base.birthDate,
                        status: base.status,
                        pastureID: base.pastureID,
                        sireID: base.sireID,
                        damID: base.damID,
                        distinguishingFeatures: base.distinguishingFeatures,
                        saleDate: base.saleDate,
                        salePrice: base.salePrice,
                        reasonSold: base.reasonSold,
                        deathDate: Date(timeIntervalSinceReferenceDate: 48_000),
                        causeOfDeath: "Replacement cause",
                        statusReferenceID: replacementReference.id
                    ),
                    tags: self.tags(from: current.animal)
                )
            }
        )
    }

    func makeAllTagsRetiredProbe() throws -> AnimalAggregateAllTagsRetiredUpdateContractProbe {
        let pasture = try makePastureRepository().create(
            input: PastureInput(
                name: "Retirement Pasture",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        let repository = makeAnimalRepository()
        let subject = try repository.create(
            input: animalInput(
                name: "Retirement Bull",
                tagNumber: "RETIRE-1",
                sex: .male,
                pastureID: pasture.id
            )
        )
        _ = try repository.create(
            input: animalInput(
                name: "Retirement Inference Dam",
                tagNumber: "RID",
                sex: .female,
                pastureID: pasture.id
            )
        )

        return AnimalAggregateAllTagsRetiredUpdateContractProbe(
            writer: makeAnimalRepository(),
            makeReader: { self.makeAnimalRepository() },
            makeAnimalRepository: { self.makeAnimalRepository() },
            makeAnimalListQueryReader: nil,
            makeDashboardQueryReader: nil,
            animalID: subject.id,
            makeUpdateTransaction: { current in
                UpdateAnimalAggregateTransaction(
                    animalID: current.animal.id,
                    expectedRevision: current.revision,
                    attributes: self.attributes(from: current.animal),
                    tags: self.tags(from: current.animal).map {
                        AnimalTagTransactionState(
                            id: $0.id,
                            number: $0.number,
                            colorID: $0.colorID,
                            isPrimary: false,
                            isActive: false
                        )
                    }
                )
            }
        )
    }

    func makeNonOwnedStatePreservationProbe() throws -> AnimalAggregateNonOwnedStatePreservationContractProbe {
        let repository = makeAnimalRepository()
        let subject = try repository.create(
            input: animalInput(
                name: "Preservation Subject",
                tagNumber: "PRESERVE-1",
                sex: .female
            )
        )
        _ = try repository.create(
            input: AnimalInput(
                name: "Preservation Offspring",
                tagNumber: "PRESERVE-CALF",
                tagColorID: nil,
                sex: .female,
                birthDate: Date(timeIntervalSinceReferenceDate: 50_000),
                status: .active,
                pastureID: nil,
                sireID: nil,
                damID: subject.id,
                distinguishingFeatures: [],
                saleDate: nil,
                salePrice: nil,
                reasonSold: nil,
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: nil
            )
        )
        _ = try repository.addHealthRecord(
            animalID: subject.id,
            input: HealthRecordInput(
                date: Date(timeIntervalSinceReferenceDate: 51_000),
                treatment: "Preserved treatment",
                notes: "Preserved health note"
            )
        )
        _ = try repository.addPregnancyCheck(
            animalID: subject.id,
            input: PregnancyCheckInput(
                date: Date(timeIntervalSinceReferenceDate: 52_000),
                result: .pregnant,
                technician: "Contract tech",
                estimatedDaysPregnant: 90,
                dueDate: Date(timeIntervalSinceReferenceDate: 53_000),
                sireAnimalID: nil
            )
        )
        try repository.archive(ids: [subject.id])
        try setArchiveReason(
            animalID: subject.id,
            reason: "Preservation archive"
        )
        _ = try seedWorkingOwnership(animalID: subject.id)

        return AnimalAggregateNonOwnedStatePreservationContractProbe(
            writer: makeAnimalRepository(),
            makeReader: { self.makeAnimalRepository() },
            makeAnimalRepository: { self.makeAnimalRepository() },
            makeAnimalListQueryReader: nil,
            makeDashboardQueryReader: nil,
            makeWorkingReader: { self.makeWorkingReader() },
            makeWorkingOwnershipControl: { self.makeWorkingOwnershipControl() },
            makeHealthControl: { self.makeHealthControl() },
            animalID: subject.id,
            makeUpdateTransaction: { current in
                UpdateAnimalAggregateTransaction(
                    animalID: current.animal.id,
                    expectedRevision: current.revision,
                    attributes: self.attributes(
                        from: current.animal,
                        name: current.animal.name + " updated"
                    ),
                    tags: self.tags(from: current.animal)
                )
            }
        )
    }

    func makeInvalidTagProbe(
        expected: AnimalAggregateTagValidationFailure,
        method: AnimalAggregateInvalidTagMethod
    ) throws -> AnimalAggregateInvalidTagContractProbe {
        let invalidTags = invalidTagStates(for: expected)
        let operation: AnimalAggregateInvalidTagOperation

        switch method {
        case .create:
            operation = .create(
                CreateAnimalAggregateTransaction(
                    animalID: UUID(),
                    attributes: AnimalAggregateAttributes(
                        name: "Invalid Create",
                        sex: .female,
                        birthDate: Date(timeIntervalSinceReferenceDate: 54_000),
                        status: .active,
                        pastureID: nil,
                        sireID: nil,
                        damID: nil,
                        distinguishingFeatures: [],
                        saleDate: nil,
                        salePrice: nil,
                        reasonSold: nil,
                        deathDate: nil,
                        causeOfDeath: nil,
                        statusReferenceID: nil
                    ),
                    tags: invalidTags
                )
            )

        case .update:
            let repository = makeAnimalRepository()
            let subject = try repository.create(
                input: animalInput(
                    name: "Invalid Update",
                    tagNumber: "INVALID-BASE",
                    sex: .female
                )
            )
            let current = try XCTUnwrap(
                makeAnimalRepository().fetchAnimalAggregateForEditing(id: subject.id)
            )
            operation = .update(
                UpdateAnimalAggregateTransaction(
                    animalID: subject.id,
                    expectedRevision: current.revision,
                    attributes: attributes(from: current.animal),
                    tags: invalidTags
                )
            )
        }

        return AnimalAggregateInvalidTagContractProbe(
            writer: makeAnimalRepository(),
            operation: operation,
            expectedFailure: expected,
            classifyError: Self.classifyTagValidationError,
            freshPersistedStateSnapshot: {
                try CoreDataContractStoreSnapshotter.snapshot(assembly: self.assembly)
            },
            recoveryProbe: .discardedWriteScope(
                verifyFailedWriteScopeWasDisposed: { true }
            )
        )
    }

    func makeRevisionProbe() throws -> AnimalAggregateRevisionContractProbe {
        let transaction = makeCreateTransaction(name: "Revision contract animal", tagNumber: "R-100")
        return AnimalAggregateRevisionContractProbe(
            writer: makeAnimalRepository(),
            makeReader: { self.makeAnimalRepository() },
            createTransaction: transaction,
            makeScalarUpdateTransaction: { current in
                UpdateAnimalAggregateTransaction(
                    animalID: current.animal.id,
                    expectedRevision: current.revision,
                    attributes: self.attributes(from: current.animal, name: current.animal.name + " updated"),
                    tags: self.tags(from: current.animal)
                )
            },
            makeTagOnlyUpdateTransaction: { current in
                var tags = self.tags(from: current.animal)
                guard !tags.isEmpty else {
                    throw CoreDataAnimalContractTestError.missingPreparedTag
                }
                let first = tags[0]
                tags[0] = AnimalTagTransactionState(
                    id: first.id,
                    number: first.number + "-T",
                    colorID: first.colorID,
                    isPrimary: first.isPrimary,
                    isActive: first.isActive
                )
                return UpdateAnimalAggregateTransaction(
                    animalID: current.animal.id,
                    expectedRevision: current.revision,
                    attributes: self.attributes(from: current.animal),
                    tags: tags
                )
            },
            makeStaleUpdateTransaction: { staleBase in
                UpdateAnimalAggregateTransaction(
                    animalID: staleBase.animal.id,
                    expectedRevision: staleBase.revision,
                    attributes: self.attributes(
                        from: staleBase.animal,
                        name: staleBase.animal.name + " stale overwrite"
                    ),
                    tags: self.tags(from: staleBase.animal)
                )
            },
            classifyError: Self.classifyPreconditionError,
            freshPersistedStateSnapshot: {
                try CoreDataContractStoreSnapshotter.snapshot(assembly: self.assembly)
            },
            recoveryProbe: .discardedWriteScope(
                verifyFailedWriteScopeWasDisposed: { true }
            )
        )
    }

    func makeMissingProbe() throws -> AnimalAggregateMissingPreconditionContractProbe {
        let repository = makeAnimalRepository()
        let created = try repository.create(
            input: makeLegacyAnimalInput(name: "Deleted aggregate", tagNumber: "D-100")
        )
        let staleBase = try XCTUnwrap(
            makeAnimalRepository().fetchAnimalAggregateForEditing(id: created.id)
        )
        let update = UpdateAnimalAggregateTransaction(
            animalID: staleBase.animal.id,
            expectedRevision: staleBase.revision,
            attributes: attributes(
                from: staleBase.animal,
                name: staleBase.animal.name + " attempted recreation"
            ),
            tags: tags(from: staleBase.animal)
        )

        return AnimalAggregateMissingPreconditionContractProbe(
            writer: makeAnimalRepository(),
            makeReader: { self.makeAnimalRepository() },
            staleBase: staleBase,
            updateTransaction: update,
            deleter: makeAnimalRepository(),
            classifyError: Self.classifyPreconditionError,
            freshPersistedStateSnapshot: {
                try CoreDataContractStoreSnapshotter.snapshot(assembly: self.assembly)
            },
            recoveryProbe: .discardedWriteScope(
                verifyFailedWriteScopeWasDisposed: { true }
            )
        )
    }

    func makeCreateRollbackProbe() throws -> AnimalAggregateCreateRollbackProbe {
        let failureState = CoreDataAnimalInjectedFailureState()
        let writer = FaultInjectingAnimalAggregateWriter(
            base: makeAnimalRepository(),
            failureState: failureState
        )

        return AnimalAggregateCreateRollbackProbe(
            writer: writer,
            transaction: makeCreateTransaction(name: "Rollback create", tagNumber: "RB-C"),
            didReachInjectedRollbackFailpoint: { failureState.didReachFailpoint },
            freshPersistedStateSnapshot: {
                try CoreDataContractStoreSnapshotter.snapshot(assembly: self.assembly)
            },
            recoveryProbe: .reusableWriteScope(
                saveFailedWriteScopeWithoutAdditionalReset: {
                    try failureState.saveCapturedContextWithoutReset()
                }
            )
        )
    }

    func makeUpdateRollbackProbe() throws -> AnimalAggregateUpdateRollbackProbe {
        let repository = makeAnimalRepository()
        let created = try repository.create(
            input: makeLegacyAnimalInput(name: "Rollback update", tagNumber: "RB-U")
        )
        let current = try XCTUnwrap(
            makeAnimalRepository().fetchAnimalAggregateForEditing(id: created.id)
        )
        let transaction = UpdateAnimalAggregateTransaction(
            animalID: current.animal.id,
            expectedRevision: current.revision,
            attributes: attributes(
                from: current.animal,
                name: current.animal.name + " staged"
            ),
            tags: tags(from: current.animal)
        )
        let failureState = CoreDataAnimalInjectedFailureState()
        let writer = FaultInjectingAnimalAggregateWriter(
            base: makeAnimalRepository(),
            failureState: failureState
        )

        return AnimalAggregateUpdateRollbackProbe(
            writer: writer,
            transaction: transaction,
            didReachInjectedRollbackFailpoint: { failureState.didReachFailpoint },
            freshPersistedStateSnapshot: {
                try CoreDataContractStoreSnapshotter.snapshot(assembly: self.assembly)
            },
            recoveryProbe: .reusableWriteScope(
                saveFailedWriteScopeWithoutAdditionalReset: {
                    try failureState.saveCapturedContextWithoutReset()
                }
            )
        )
    }

    func makePastureDeletionInvalidPlanProbe() throws -> PastureDeletionInvalidPlanContractProbe {
        let pastures = makePastureRepository()
        let first = try pastures.create(
            input: PastureInput(name: "Invalid plan first", acreage: 10, usableAcreage: 9, targetAcresPerHead: 1)
        )
        let second = try pastures.create(
            input: PastureInput(name: "Invalid plan second", acreage: 11, usableAcreage: 10, targetAcresPerHead: 1)
        )
        let resident = try makeAnimalRepository().create(
            input: animalInput(
                name: "Invalid plan resident",
                tagNumber: "M6-INVALID",
                sex: .female,
                pastureID: first.id
            )
        )
        let expected = [
            PastureDeletionExpectedState(
                pastureID: first.id,
                residentAnimalIDs: [resident.id]
            ),
            PastureDeletionExpectedState(
                pastureID: second.id,
                residentAnimalIDs: []
            )
        ]
        let archive = PastureDeletionOperation.archiveFieldChecks(
            pastureIDs: [first.id, second.id],
            archivedAt: Date(timeIntervalSinceReferenceDate: 79_000)
        )
        let delete = PastureDeletionOperation.deletePastures(ids: [first.id, second.id])
        let move = PastureDeletionOperation.moveAnimals(
            animalIDs: [resident.id],
            fromPastureID: first.id,
            toPastureID: nil
        )
        let unknownPastureID = UUID()

        let cases = [
            PastureDeletionInvalidPlanContractCase(
                name: "empty expected state",
                plan: DeletePasturesTransactionPlan(expectedStates: [], operations: [])
            ),
            PastureDeletionInvalidPlanContractCase(
                name: "duplicate expected Pasture",
                plan: DeletePasturesTransactionPlan(
                    expectedStates: [expected[0], expected[0]],
                    operations: [move, archive, delete]
                )
            ),
            PastureDeletionInvalidPlanContractCase(
                name: "missing Field Check archive",
                plan: DeletePasturesTransactionPlan(
                    expectedStates: expected,
                    operations: [move, delete]
                )
            ),
            PastureDeletionInvalidPlanContractCase(
                name: "archive target mismatch",
                plan: DeletePasturesTransactionPlan(
                    expectedStates: expected,
                    operations: [
                        move,
                        .archiveFieldChecks(
                            pastureIDs: [first.id],
                            archivedAt: Date(timeIntervalSinceReferenceDate: 79_100)
                        ),
                        delete
                    ]
                )
            ),
            PastureDeletionInvalidPlanContractCase(
                name: "delete target mismatch",
                plan: DeletePasturesTransactionPlan(
                    expectedStates: expected,
                    operations: [
                        move,
                        archive,
                        .deletePastures(ids: [first.id])
                    ]
                )
            ),
            PastureDeletionInvalidPlanContractCase(
                name: "move after archive",
                plan: DeletePasturesTransactionPlan(
                    expectedStates: expected,
                    operations: [archive, move, delete]
                )
            ),
            PastureDeletionInvalidPlanContractCase(
                name: "move source outside target set",
                plan: DeletePasturesTransactionPlan(
                    expectedStates: expected,
                    operations: [
                        .moveAnimals(
                            animalIDs: [resident.id],
                            fromPastureID: unknownPastureID,
                            toPastureID: nil
                        ),
                        archive,
                        delete
                    ]
                )
            ),
            PastureDeletionInvalidPlanContractCase(
                name: "move destination is also deleted",
                plan: DeletePasturesTransactionPlan(
                    expectedStates: expected,
                    operations: [
                        .moveAnimals(
                            animalIDs: [resident.id],
                            fromPastureID: first.id,
                            toPastureID: second.id
                        ),
                        archive,
                        delete
                    ]
                )
            ),
            PastureDeletionInvalidPlanContractCase(
                name: "duplicate Animal identity in move",
                plan: DeletePasturesTransactionPlan(
                    expectedStates: expected,
                    operations: [
                        .moveAnimals(
                            animalIDs: [resident.id, resident.id],
                            fromPastureID: first.id,
                            toPastureID: nil
                        ),
                        archive,
                        delete
                    ]
                )
            ),
            PastureDeletionInvalidPlanContractCase(
                name: "authored resident set does not match moves",
                plan: DeletePasturesTransactionPlan(
                    expectedStates: expected,
                    operations: [archive, delete]
                )
            ),
            PastureDeletionInvalidPlanContractCase(
                name: "operation follows final delete",
                plan: DeletePasturesTransactionPlan(
                    expectedStates: expected,
                    operations: [
                        move,
                        archive,
                        delete,
                        .archiveFieldChecks(
                            pastureIDs: [first.id, second.id],
                            archivedAt: Date(timeIntervalSinceReferenceDate: 79_200)
                        )
                    ]
                )
            )
        ]

        return PastureDeletionInvalidPlanContractProbe(
            writer: CoreDataPastureDeletionTransactionWriter(
                selection: selection,
                assembly: assembly
            ),
            cases: cases,
            freshPersistedStateSnapshot: {
                try CoreDataContractStoreSnapshotter.snapshot(assembly: self.assembly)
            }
        )
    }

    func contractAnimalInput(
        name: String,
        tagNumber: String,
        pastureID: UUID?
    ) -> AnimalInput {
        animalInput(
            name: name,
            tagNumber: tagNumber,
            sex: .female,
            pastureID: pastureID
        )
    }

    func seedFieldCheckSession(
        pastureID: UUID,
        pastureName: String
    ) throws -> UUID {
        let id = UUID()
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            guard let herd = try assembly.lookup.herd(id: herdID, in: context),
                  let pasture = try assembly.lookup.herdOwned(
                    CDPasture.self,
                    id: pastureID,
                    herdID: herdID,
                    in: context
                  ) else {
                throw CoreDataAnimalContractTestError.missingPreparedPasture
            }
            let session = CDFieldCheckSession(context: context)
            session.id = id
            session.startedAt = Date(timeIntervalSinceReferenceDate: 70_000)
            session.completedAt = nil
            session.notes = "M6 historical session"
            session.expectedHeadCountSnapshot = 1
            session.quickCowCount = 0
            session.quickHeiferCount = 0
            session.quickCalfCount = 0
            session.quickBullCount = 0
            session.quickSteerCount = 0
            session.pastureIDSnapshot = pastureID
            session.pastureNameSnapshot = pastureName
            session.pastureArchivedAt = nil
            session.herd = herd
            session.pasture = pasture
            try context.save()
        }
        return id
    }

    func fieldCheckArchiveState(id: UUID) throws -> CoreDataFieldCheckArchiveState {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let session = try assembly.lookup.herdOwned(
                CDFieldCheckSession.self,
                id: id,
                herdID: herdID,
                in: context
            ) else {
                throw CoreDataAnimalContractTestError.missingPreparedFieldCheck
            }
            return CoreDataFieldCheckArchiveState(
                pastureIDSnapshot: session.pastureIDSnapshot,
                pastureNameSnapshot: session.pastureNameSnapshot,
                pastureArchivedAt: session.pastureArchivedAt,
                livePastureID: session.pasture?.id
            )
        }
    }

    func makePastureResidentSetChangedProbe() throws -> PastureDeletionPreconditionContractProbe {
        let pastureRepository = makePastureRepository()
        let first = try pastureRepository.create(
            input: PastureInput(name: "Stale resident first", acreage: 10, usableAcreage: 9, targetAcresPerHead: 1)
        )
        let stale = try pastureRepository.create(
            input: PastureInput(name: "Stale resident second", acreage: 11, usableAcreage: 10, targetAcresPerHead: 1)
        )
        let plan = emptyPastureDeletionPlan(ids: [first.id, stale.id])

        _ = try makeAnimalRepository().create(
            input: animalInput(
                name: "Late resident",
                tagNumber: "M6-LATE",
                sex: .female,
                pastureID: stale.id
            )
        )

        return PastureDeletionPreconditionContractProbe(
            writer: CoreDataPastureDeletionTransactionWriter(selection: selection, assembly: assembly),
            plan: plan,
            expectedFailure: .pastureResidentSetChanged(pastureID: stale.id),
            classifyError: Self.classifyPastureDeletionPreconditionError,
            freshPersistedStateSnapshot: {
                try CoreDataContractStoreSnapshotter.snapshot(assembly: self.assembly)
            },
            recoveryProbe: .discardedWriteScope(
                verifyFailedWriteScopeWasDisposed: { true }
            )
        )
    }

    func makePastureMissingProbe() throws -> PastureDeletionPreconditionContractProbe {
        let pastureRepository = makePastureRepository()
        let first = try pastureRepository.create(
            input: PastureInput(name: "Missing first", acreage: 10, usableAcreage: 9, targetAcresPerHead: 1)
        )
        let missing = try pastureRepository.create(
            input: PastureInput(name: "Missing second", acreage: 11, usableAcreage: 10, targetAcresPerHead: 1)
        )
        let plan = emptyPastureDeletionPlan(ids: [first.id, missing.id])
        try pastureRepository.delete(ids: [missing.id])

        return PastureDeletionPreconditionContractProbe(
            writer: CoreDataPastureDeletionTransactionWriter(selection: selection, assembly: assembly),
            plan: plan,
            expectedFailure: .pastureMissing(pastureID: missing.id),
            classifyError: Self.classifyPastureDeletionPreconditionError,
            freshPersistedStateSnapshot: {
                try CoreDataContractStoreSnapshotter.snapshot(assembly: self.assembly)
            },
            recoveryProbe: .discardedWriteScope(
                verifyFailedWriteScopeWasDisposed: { true }
            )
        )
    }

    func makePastureDeletionRevisionControl() throws -> CoreDataPastureDeletionRevisionControl {
        let pasture = try makePastureRepository().create(
            input: PastureInput(name: "Revision target", acreage: 16, usableAcreage: 15, targetAcresPerHead: 1)
        )
        let animalRepository = makeAnimalRepository()
        let active = try animalRepository.create(
            input: animalInput(
                name: "Revision active resident",
                tagNumber: "M6-REV-A",
                sex: .female,
                pastureID: pasture.id
            )
        )
        let inactive = try animalRepository.create(
            input: animalInput(
                name: "Revision archived resident",
                tagNumber: "M6-REV-I",
                sex: .female,
                pastureID: pasture.id
            )
        )
        try animalRepository.archive(ids: [inactive.id])
        let unrelated = try animalRepository.create(
            input: animalInput(
                name: "Revision unrelated",
                tagNumber: "M6-REV-U",
                sex: .female
            )
        )
        let plan = DeletePasturesTransactionPlan(
            expectedStates: [
                PastureDeletionExpectedState(
                    pastureID: pasture.id,
                    residentAnimalIDs: [active.id]
                )
            ],
            operations: [
                .moveAnimals(
                    animalIDs: [active.id],
                    fromPastureID: pasture.id,
                    toPastureID: nil
                ),
                .archiveFieldChecks(
                    pastureIDs: [pasture.id],
                    archivedAt: Date(timeIntervalSinceReferenceDate: 92_000)
                ),
                .deletePastures(ids: [pasture.id])
            ]
        )

        return CoreDataPastureDeletionRevisionControl(
            assembly: assembly,
            selection: selection,
            plan: plan,
            activeResidentID: active.id,
            inactiveSurvivorID: inactive.id,
            unrelatedAnimalID: unrelated.id
        )
    }

    func makePastureDeletionRollbackProbe() throws -> PastureDeletionRollbackProbe {
        let pasture = try makePastureRepository().create(
            input: PastureInput(name: "Rollback pasture", acreage: 12, usableAcreage: 11, targetAcresPerHead: 1)
        )
        let resident = try makeAnimalRepository().create(
            input: animalInput(
                name: "Rollback resident",
                tagNumber: "M6-RB",
                sex: .female,
                pastureID: pasture.id
            )
        )
        let archivedAt = Date(timeIntervalSinceReferenceDate: 90_000)
        let plan = DeletePasturesTransactionPlan(
            expectedStates: [
                PastureDeletionExpectedState(
                    pastureID: pasture.id,
                    residentAnimalIDs: [resident.id]
                )
            ],
            operations: [
                .moveAnimals(
                    animalIDs: [resident.id],
                    fromPastureID: pasture.id,
                    toPastureID: nil
                ),
                .archiveFieldChecks(pastureIDs: [pasture.id], archivedAt: archivedAt),
                .deletePastures(ids: [pasture.id])
            ]
        )
        let failureState = CoreDataAnimalInjectedFailureState()
        let base = CoreDataPastureDeletionTransactionWriter(selection: selection, assembly: assembly)
        let writer = FaultInjectingPastureDeletionWriter(base: base, failureState: failureState)

        return PastureDeletionRollbackProbe(
            writer: writer,
            plan: plan,
            didReachInjectedRollbackFailpoint: { failureState.didReachFailpoint },
            freshPersistedStateSnapshot: {
                try CoreDataContractStoreSnapshotter.snapshot(assembly: self.assembly)
            },
            recoveryProbe: .reusableWriteScope(
                saveFailedWriteScopeWithoutAdditionalReset: {
                    try failureState.saveCapturedContextWithoutReset()
                }
            )
        )
    }

    private func emptyPastureDeletionPlan(ids: [UUID]) -> DeletePasturesTransactionPlan {
        let archivedAt = Date(timeIntervalSinceReferenceDate: 80_000)
        return DeletePasturesTransactionPlan(
            expectedStates: ids.map {
                PastureDeletionExpectedState(pastureID: $0, residentAnimalIDs: [])
            },
            operations: [
                .archiveFieldChecks(pastureIDs: ids, archivedAt: archivedAt),
                .deletePastures(ids: ids)
            ]
        )
    }

    private static func classifyPastureDeletionPreconditionError(
        _ error: Error
    ) -> PersistenceTransactionPreconditionFailure? {
        guard let error = error as? PastureDeletionTransactionError else {
            return nil
        }
        switch error {
        case .pastureMissing(let pastureID):
            return .pastureMissing(pastureID: pastureID)
        case .residentSetChanged(let pastureID):
            return .pastureResidentSetChanged(pastureID: pastureID)
        default:
            return nil
        }
    }

    func makeWorkingOwnershipControl() -> CoreDataAnimalWorkingOwnershipControl {
        CoreDataAnimalWorkingOwnershipControl(
            assembly: assembly,
            herdID: herdID
        )
    }

    func makeWorkingReader() -> CoreDataAnimalWorkingSessionReader {
        CoreDataAnimalWorkingSessionReader(
            assembly: assembly,
            herdID: herdID
        )
    }

    func makeHealthControl() -> CoreDataAnimalHealthContractControl {
        CoreDataAnimalHealthContractControl(
            assembly: assembly,
            herdID: herdID
        )
    }

    private func setArchiveReason(
        animalID: UUID,
        reason: String
    ) throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            guard let animal = try assembly.lookup.herdOwned(
                CDAnimal.self,
                id: animalID,
                herdID: herdID,
                in: context
            ) else {
                throw AnimalValidationError.animalNotFound
            }
            animal.archiveReason = reason
            try context.save()
        }
    }

    private func seedWorkingOwnership(animalID: UUID) throws -> UUID {
        let supportPasture = try makePastureRepository().create(
            input: PastureInput(
                name: "Working History Source",
                acreage: 10,
                usableAcreage: 9,
                targetAcresPerHead: 1.5
            )
        )
        let detail = try XCTUnwrap(
            makeAnimalRepository().fetchAnimalDetail(id: animalID)
        )
        let context = try assembly.contextFactory.makeWriteContext()
        let sessionID = UUID()
        try context.performAndWait {
            guard let herd = try assembly.lookup.herd(id: herdID, in: context),
                  let animal = try assembly.lookup.herdOwned(
                    CDAnimal.self,
                    id: animalID,
                    herdID: herdID,
                    in: context
                  ),
                  let pasture = try assembly.lookup.herdOwned(
                    CDPasture.self,
                    id: supportPasture.id,
                    herdID: herdID,
                    in: context
                  ) else {
                throw HerdRepositoryError.missingHerd
            }

            let session = CDWorkingSession(context: context)
            session.id = sessionID
            session.date = Date(timeIntervalSinceReferenceDate: 55_000)
            session.statusRawValue = WorkingSessionStatus.active.rawValue
            session.treatmentTemplateNameSnapshot = ""
            session.plannedTreatmentsData = try JSONEncoder().encode(
                [WorkingTreatmentPlanItem]()
            )
            session.sourcePastureIDSnapshot = supportPasture.id
            session.sourcePastureNameSnapshot = supportPasture.name
            session.herd = herd
            session.sourcePasture = pasture

            let queue = CDWorkingQueueItem(context: context)
            queue.id = UUID()
            queue.statusRawValue = WorkingQueueStatus.queued.rawValue
            queue.completedAt = nil
            queue.animalIDSnapshot = animalID
            queue.animalTagNumberSnapshot = detail.displayTagNumber
            queue.animalTagColorIDSnapshot = detail.displayTagColorID
            queue.animalNameSnapshot = detail.name
            queue.animalSexRawValueSnapshot = detail.sex.rawValue
            queue.animalDamDisplayTagNumberSnapshot = detail.dam
            queue.animalDamDisplayTagColorIDSnapshot = nil
            queue.collectedFromPastureIDSnapshot = nil
            queue.collectedFromPastureNameSnapshot = nil
            queue.destinationPastureIDSnapshot = nil
            queue.destinationPastureNameSnapshot = nil
            queue.herd = herd
            queue.session = session
            queue.animal = animal
            queue.collectedFromPasture = nil
            queue.destinationPasture = nil

            animal.currentPasture = nil
            animal.activeWorkingSession = session
            try context.save()
        }
        return sessionID
    }

    private func animalInput(
        name: String,
        tagNumber: String,
        sex: Sex,
        pastureID: UUID? = nil
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: sex,
            birthDate: Date(timeIntervalSinceReferenceDate: 30_000),
            status: .active,
            pastureID: pastureID,
            sireID: nil,
            damID: nil,
            distinguishingFeatures: [],
            saleDate: nil,
            salePrice: nil,
            reasonSold: nil,
            deathDate: nil,
            causeOfDeath: nil,
            statusReferenceID: nil
        )
    }

    private func invalidTagStates(
        for failure: AnimalAggregateTagValidationFailure
    ) -> [AnimalTagTransactionState] {
        let firstID = UUID()
        switch failure {
        case .activeTagsRequirePrimary:
            return [
                AnimalTagTransactionState(
                    id: firstID,
                    number: "INVALID-NO-PRIMARY",
                    colorID: nil,
                    isPrimary: false,
                    isActive: true
                )
            ]

        case .multipleActivePrimaryTags:
            return [
                AnimalTagTransactionState(
                    id: firstID,
                    number: "INVALID-P1",
                    colorID: nil,
                    isPrimary: true,
                    isActive: true
                ),
                AnimalTagTransactionState(
                    id: UUID(),
                    number: "INVALID-P2",
                    colorID: nil,
                    isPrimary: true,
                    isActive: true
                )
            ]

        case .inactiveTagCannotBePrimary:
            return [
                AnimalTagTransactionState(
                    id: firstID,
                    number: "INVALID-RETIRED-PRIMARY",
                    colorID: nil,
                    isPrimary: true,
                    isActive: false
                )
            ]

        case .duplicateTagApplicationIDs:
            return [
                AnimalTagTransactionState(
                    id: firstID,
                    number: "INVALID-DUP-1",
                    colorID: nil,
                    isPrimary: true,
                    isActive: true
                ),
                AnimalTagTransactionState(
                    id: firstID,
                    number: "INVALID-DUP-2",
                    colorID: nil,
                    isPrimary: false,
                    isActive: true
                )
            ]
        }
    }

    private static func classifyTagValidationError(
        _ error: Error
    ) -> AnimalAggregateTagValidationFailure? {
        guard let error = error as? AnimalAggregateTransactionError else {
            return nil
        }
        switch error {
        case .activeTagsRequirePrimary:
            return .activeTagsRequirePrimary
        case .multipleActivePrimaryTags:
            return .multipleActivePrimaryTags
        case .inactiveTagCannotBePrimary:
            return .inactiveTagCannotBePrimary
        case .duplicateTagApplicationIDs:
            return .duplicateTagApplicationIDs
        case .aggregateNotFound, .staleRevision:
            return nil
        }
    }

    private func seedHerd() throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = CDHerd(context: context)
            herd.id = herdID
            herd.name = "Animal Contract Herd"
            herd.createdAt = Date(timeIntervalSinceReferenceDate: 1_000)
            herd.updatedAt = herd.createdAt
            try context.save()
        }
    }

    private func makeStatusReference(
        name: String,
        baseStatus: AnimalStatus
    ) throws -> AnimalStatusReferenceOption {
        let context = try assembly.contextFactory.makeWriteContext()
        let id = UUID()
        try context.performAndWait {
            guard let herd = try assembly.lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            let reference = CDAnimalStatusReference(context: context)
            reference.id = id
            reference.name = name
            reference.baseStatusRawValue = baseStatus.rawValue
            reference.herd = herd
            try context.save()
        }
        return AnimalStatusReferenceOption(id: id, name: name, baseStatus: baseStatus)
    }

    func makeCreateTransaction(
        name: String,
        tagNumber: String,
        colorID: UUID? = nil,
        pastureID: UUID? = nil
    ) -> CreateAnimalAggregateTransaction {
        CreateAnimalAggregateTransaction(
            animalID: UUID(),
            attributes: AnimalAggregateAttributes(
                name: name,
                sex: .female,
                birthDate: Date(timeIntervalSinceReferenceDate: 10_000),
                status: .active,
                pastureID: nil,
                sireID: nil,
                damID: nil,
                distinguishingFeatures: [
                    DistinguishingFeature(description: "Contract blaze", order: 0)
                ],
                saleDate: nil,
                salePrice: nil,
                reasonSold: nil,
                deathDate: nil,
                causeOfDeath: nil,
                statusReferenceID: nil
            ),
            tags: [
                AnimalTagTransactionState(
                    id: UUID(),
                    number: tagNumber,
                    colorID: colorID,
                    isPrimary: true,
                    isActive: true
                )
            ]
        )
    }

    private func makeLegacyAnimalInput(
        name: String,
        tagNumber: String
    ) -> AnimalInput {
        AnimalInput(
            name: name,
            tagNumber: tagNumber,
            tagColorID: nil,
            sex: .female,
            birthDate: Date(timeIntervalSinceReferenceDate: 20_000),
            status: .active,
            pastureID: nil,
            sireID: nil,
            damID: nil,
            distinguishingFeatures: [],
            saleDate: nil,
            salePrice: nil,
            reasonSold: nil,
            deathDate: nil,
            causeOfDeath: nil,
            statusReferenceID: nil
        )
    }

    func attributes(
        from detail: AnimalDetailSnapshot,
        name: String? = nil
    ) -> AnimalAggregateAttributes {
        AnimalAggregateAttributes(
            name: name ?? detail.name,
            sex: detail.sex,
            birthDate: detail.birthDate,
            status: detail.status,
            pastureID: detail.pastureID,
            sireID: detail.sireID,
            damID: detail.damID,
            distinguishingFeatures: detail.distinguishingFeatures,
            saleDate: detail.saleDate,
            salePrice: detail.salePrice,
            reasonSold: detail.reasonSold,
            deathDate: detail.deathDate,
            causeOfDeath: detail.causeOfDeath,
            statusReferenceID: detail.statusReferenceID
        )
    }

    func tags(from detail: AnimalDetailSnapshot) -> [AnimalTagTransactionState] {
        (detail.activeTags + detail.inactiveTags).map {
            AnimalTagTransactionState(
                id: $0.id,
                number: $0.number,
                colorID: $0.colorID,
                isPrimary: $0.isPrimary,
                isActive: $0.isActive
            )
        }
    }

    private static func classifyPreconditionError(
        _ error: Error
    ) -> PersistenceTransactionPreconditionFailure? {
        guard let error = error as? AnimalAggregateTransactionError else {
            return nil
        }
        switch error {
        case .staleRevision(let animalID):
            return .staleAnimalAggregate(animalID: animalID)
        case .aggregateNotFound(let animalID):
            return .animalAggregateMissing(animalID: animalID)
        default:
            return nil
        }
    }
}

@MainActor
private final class CoreDataAnimalContractSelection: CurrentHerdSelectionReading {
    var currentHerdID: UUID?
}

private enum CoreDataAnimalContractTestError: Error {
    case missingPreparedTag
    case injectedFailure
    case missingCapturedWriteContext
    case unsupportedIdentityKind
    case invalidWorkingSessionStatus
    case invalidWorkingQueueStatus
    case invalidWorkingAnimalSex
    case missingPreparedPasture
    case missingPreparedFieldCheck
}

@MainActor
private final class CoreDataAnimalWorkingOwnershipControl:
    AnimalAggregateWorkingOwnershipContractTestControl
{
    private let assembly: CoreDataPersistenceAssembly
    private let herdID: UUID

    init(
        assembly: CoreDataPersistenceAssembly,
        herdID: UUID
    ) {
        self.assembly = assembly
        self.herdID = herdID
    }

    func activeWorkingSessionID(forAnimalID animalID: UUID) throws -> UUID? {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            try assembly.lookup.herdOwned(
                CDAnimal.self,
                id: animalID,
                herdID: herdID,
                in: context
            )?.activeWorkingSession?.id
        }
    }
}

@MainActor
private final class CoreDataAnimalWorkingSessionReader: WorkingSessionDetailReader {
    private let assembly: CoreDataPersistenceAssembly
    private let herdID: UUID

    init(
        assembly: CoreDataPersistenceAssembly,
        herdID: UUID
    ) {
        self.assembly = assembly
        self.herdID = herdID
    }

    func fetchSessionDetail(id: UUID) throws -> WorkingSessionDetailSnapshot? {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let session = try assembly.lookup.herdOwned(
                CDWorkingSession.self,
                id: id,
                herdID: herdID,
                in: context
            ) else {
                return nil
            }
            guard let status = WorkingSessionStatus(rawValue: session.statusRawValue) else {
                throw CoreDataAnimalContractTestError.invalidWorkingSessionStatus
            }
            let plannedTreatments = try JSONDecoder().decode(
                [WorkingTreatmentPlanItem].self,
                from: session.plannedTreatmentsData
            )
            let queueItems = try ((session.queueItems?.allObjects as? [CDWorkingQueueItem]) ?? [])
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { item -> WorkingQueueItemSnapshot in
                    guard let queueStatus = WorkingQueueStatus(rawValue: item.statusRawValue) else {
                        throw CoreDataAnimalContractTestError.invalidWorkingQueueStatus
                    }
                    guard let sex = Sex(rawValue: item.animalSexRawValueSnapshot) else {
                        throw CoreDataAnimalContractTestError.invalidWorkingAnimalSex
                    }
                    return WorkingQueueItemSnapshot(
                        id: item.id,
                        status: queueStatus,
                        completedAt: item.completedAt,
                        animalID: item.animalIDSnapshot,
                        animalName: item.animalNameSnapshot,
                        animalDisplayTagNumber: item.animalTagNumberSnapshot,
                        animalDisplayTagColorID: item.animalTagColorIDSnapshot,
                        animalDamDisplayTagNumber: item.animalDamDisplayTagNumberSnapshot,
                        animalDamDisplayTagColorID: item.animalDamDisplayTagColorIDSnapshot,
                        animalSex: sex,
                        collectedFromPastureID: item.collectedFromPastureIDSnapshot,
                        collectedFromPastureName: item.collectedFromPastureNameSnapshot,
                        destinationPastureID: item.destinationPastureIDSnapshot,
                        destinationPastureName: item.destinationPastureNameSnapshot
                    )
                }

            return WorkingSessionDetailSnapshot(
                id: session.id,
                date: session.date,
                status: status,
                sourcePastureID: session.sourcePastureIDSnapshot,
                sourcePastureName: session.sourcePastureNameSnapshot,
                isSourcePastureAvailable: session.sourcePasture != nil,
                treatmentTemplateName: session.treatmentTemplateNameSnapshot,
                plannedTreatments: plannedTreatments,
                queueItems: queueItems
            )
        }
    }
}

@MainActor
private final class CoreDataAnimalHealthContractControl: HealthRepositoryContractTestControl {
    private let assembly: CoreDataPersistenceAssembly
    private let herdID: UUID

    init(
        assembly: CoreDataPersistenceAssembly,
        herdID: UUID
    ) {
        self.assembly = assembly
        self.herdID = herdID
    }

    func healthRecords(
        forAnimalID animalID: UUID
    ) throws -> [HealthRecordContractSnapshot] {
        try allHealthRecords().filter { $0.animalID == animalID }
    }

    func pregnancyChecks(
        forAnimalID animalID: UUID
    ) throws -> [PregnancyCheckContractSnapshot] {
        try allPregnancyChecks().filter { $0.animalID == animalID }
    }

    func allHealthRecords() throws -> [HealthRecordContractSnapshot] {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDHealthRecord>(
                entityName: CDHealthRecord.coreDataEntityName
            )
            request.predicate = NSPredicate(
                format: "herd.id == %@",
                herdID as NSUUID
            )
            return try context.fetch(request).map {
                HealthRecordContractSnapshot(
                    id: $0.id,
                    animalID: $0.animal.id,
                    date: $0.date,
                    treatment: $0.treatment,
                    notes: $0.notes,
                    workingSessionID: $0.workingSession?.id
                )
            }
        }
    }

    func allPregnancyChecks() throws -> [PregnancyCheckContractSnapshot] {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let request = NSFetchRequest<CDPregnancyCheck>(
                entityName: CDPregnancyCheck.coreDataEntityName
            )
            request.predicate = NSPredicate(
                format: "herd.id == %@",
                herdID as NSUUID
            )
            return try context.fetch(request).map {
                PregnancyCheckContractSnapshot(
                    id: $0.id,
                    animalID: $0.animal.id,
                    date: $0.date,
                    resultRawValue: $0.resultRawValue,
                    technician: $0.technician,
                    estimatedDaysPregnant: $0.estimatedDaysPregnant?.intValue,
                    dueDate: $0.dueDate,
                    sireAnimalID: $0.sire?.id,
                    workingSessionID: $0.workingSession?.id
                )
            }
        }
    }
}

@MainActor
private final class FaultInjectingAnimalAggregateWriter: AnimalAggregateTransactionWriting {
    private let base: CoreDataAnimalRepository
    private let failureState: CoreDataAnimalInjectedFailureState

    init(
        base: CoreDataAnimalRepository,
        failureState: CoreDataAnimalInjectedFailureState
    ) {
        self.base = base
        self.failureState = failureState
    }

    func createAnimal(
        _ transaction: CreateAnimalAggregateTransaction
    ) async throws -> AnimalAggregateEditSnapshot {
        let failureState = self.failureState
        return try await base.createAnimal(transaction) { context in
            failureState.capture(context)
            throw CoreDataAnimalContractTestError.injectedFailure
        }
    }

    func updateAnimal(
        _ transaction: UpdateAnimalAggregateTransaction
    ) async throws -> AnimalAggregateEditSnapshot {
        let failureState = self.failureState
        return try await base.updateAnimal(transaction) { context in
            failureState.capture(context)
            throw CoreDataAnimalContractTestError.injectedFailure
        }
    }
}

private struct CoreDataFieldCheckArchiveState: Equatable {
    let pastureIDSnapshot: UUID
    let pastureNameSnapshot: String
    let pastureArchivedAt: Date?
    let livePastureID: UUID?
}

@MainActor
private final class CoreDataPastureDeletionRevisionControl:
    AnimalAggregateCrossFeatureRevisionContractTestControl
{
    let operation: AnimalAggregateCrossFeatureRevisionOperation = .pastureDeletionTransaction
    let affectedAnimalIDs: [UUID]
    let pastureDeletionInactiveSurvivorAnimalID: UUID?
    let unrelatedAnimalID: UUID

    private let assembly: CoreDataPersistenceAssembly
    private let selection: CoreDataAnimalContractSelection
    private let plan: DeletePasturesTransactionPlan

    init(
        assembly: CoreDataPersistenceAssembly,
        selection: CoreDataAnimalContractSelection,
        plan: DeletePasturesTransactionPlan,
        activeResidentID: UUID,
        inactiveSurvivorID: UUID,
        unrelatedAnimalID: UUID
    ) {
        self.assembly = assembly
        self.selection = selection
        self.plan = plan
        self.affectedAnimalIDs = [activeResidentID, inactiveSurvivorID]
        self.pastureDeletionInactiveSurvivorAnimalID = inactiveSurvivorID
        self.unrelatedAnimalID = unrelatedAnimalID
    }

    func makeAggregateReader() -> any AnimalAggregateEditReading {
        CoreDataAnimalRepository(selection: selection, assembly: assembly)
    }

    func makeAnimalRepository() -> any AnimalRepository {
        CoreDataAnimalRepository(selection: selection, assembly: assembly)
    }

    func performMutation() async throws {
        try await CoreDataPastureDeletionTransactionWriter(
            selection: selection,
            assembly: assembly
        ).deletePastures(plan)
    }
}

@MainActor
private final class FaultInjectingPastureDeletionWriter: PastureDeletionTransactionWriting {
    private let base: CoreDataPastureDeletionTransactionWriter
    private let failureState: CoreDataAnimalInjectedFailureState

    init(
        base: CoreDataPastureDeletionTransactionWriter,
        failureState: CoreDataAnimalInjectedFailureState
    ) {
        self.base = base
        self.failureState = failureState
    }

    func deletePastures(_ plan: DeletePasturesTransactionPlan) async throws {
        let failureState = self.failureState
        try await base.deletePastures(plan) { context in
            failureState.capture(context)
            throw CoreDataAnimalContractTestError.injectedFailure
        }
    }
}

private final class CoreDataAnimalInjectedFailureState: @unchecked Sendable {
    private let lock = NSLock()
    private var reached = false
    private var capturedContext: NSManagedObjectContext?

    var didReachFailpoint: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reached
    }

    func capture(_ context: NSManagedObjectContext) {
        lock.lock()
        reached = true
        capturedContext = context
        lock.unlock()
    }

    func saveCapturedContextWithoutReset() throws {
        lock.lock()
        let context = capturedContext
        lock.unlock()

        guard let context else {
            throw CoreDataAnimalContractTestError.missingCapturedWriteContext
        }
        try context.performAndWait {
            try context.save()
        }
    }
}

@MainActor
private final class CoreDataAnimalIdentityContractScope {
    private let kind: IdentityContractEntityKind
    private let assembly: CoreDataPersistenceAssembly
    private let herdID = UUID()
    private let originalTagOwnerID = UUID()
    private let unrelatedTagOwnerID = UUID()
    private let duplicateTagOwnerID = UUID()

    init(
        kind: IdentityContractEntityKind,
        assembly: CoreDataPersistenceAssembly
    ) throws {
        guard kind == .animal || kind == .animalTag else {
            throw CoreDataAnimalContractTestError.unsupportedIdentityKind
        }
        self.kind = kind
        self.assembly = assembly
        try seedSupportGraph()
    }

    func makeControl() -> CoreDataAnimalIdentityContractControl {
        CoreDataAnimalIdentityContractControl(
            kind: kind,
            assembly: assembly,
            herdID: herdID,
            originalTagOwnerID: originalTagOwnerID,
            unrelatedTagOwnerID: unrelatedTagOwnerID,
            duplicateTagOwnerID: duplicateTagOwnerID
        )
    }

    private func seedSupportGraph() throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let herd = CDHerd(context: context)
            herd.id = herdID
            herd.name = "Identity Herd"
            herd.createdAt = Date(timeIntervalSinceReferenceDate: 100)
            herd.updatedAt = herd.createdAt

            if kind == .animalTag {
                try seedSupportAnimal(
                    id: originalTagOwnerID,
                    name: "Original tag owner",
                    herd: herd,
                    context: context
                )
                try seedSupportAnimal(
                    id: unrelatedTagOwnerID,
                    name: "Unrelated tag owner",
                    herd: herd,
                    context: context
                )
                try seedSupportAnimal(
                    id: duplicateTagOwnerID,
                    name: "Duplicate tag owner",
                    herd: herd,
                    context: context
                )
            }

            try context.save()
        }
    }

    private func seedSupportAnimal(
        id: UUID,
        name: String,
        herd: CDHerd,
        context: NSManagedObjectContext
    ) throws {
        let animal = CDAnimal(context: context)
        animal.id = id
        animal.editorRevision = UUID()
        animal.name = name
        animal.sexRawValue = Sex.female.rawValue
        animal.birthDate = Date(timeIntervalSinceReferenceDate: 1_000)
        animal.statusRawValue = AnimalStatus.active.rawValue
        animal.saleDate = nil
        animal.salePrice = nil
        animal.reasonSold = nil
        animal.deathDate = nil
        animal.causeOfDeath = nil
        animal.isArchived = false
        animal.archivedAt = nil
        animal.archiveReason = nil
        animal.distinguishingFeaturesData = try CoreDataAnimalPayloadCodec
            .encodeDistinguishingFeatures([])
        animal.herd = herd
        animal.statusReference = nil
        animal.currentPasture = nil
        animal.sire = nil
        animal.dam = nil
        animal.activeWorkingSession = nil
    }
}

@MainActor
private final class CoreDataAnimalIdentityContractControl: IdentityContractTestControl {
    private let kind: IdentityContractEntityKind
    private let assembly: CoreDataPersistenceAssembly
    private let herdID: UUID
    private let originalTagOwnerID: UUID
    private let unrelatedTagOwnerID: UUID
    private let duplicateTagOwnerID: UUID

    init(
        kind: IdentityContractEntityKind,
        assembly: CoreDataPersistenceAssembly,
        herdID: UUID,
        originalTagOwnerID: UUID,
        unrelatedTagOwnerID: UUID,
        duplicateTagOwnerID: UUID
    ) {
        self.kind = kind
        self.assembly = assembly
        self.herdID = herdID
        self.originalTagOwnerID = originalTagOwnerID
        self.unrelatedTagOwnerID = unrelatedTagOwnerID
        self.duplicateTagOwnerID = duplicateTagOwnerID
    }

    func identityScopeHerdID(
        for kind: IdentityContractEntityKind
    ) throws -> UUID? {
        try requireOwnedKind(kind)
        return herdID
    }

    func seedEntity(
        _ kind: IdentityContractEntityKind,
        id: UUID,
        variant: IdentityContractSeedVariant,
        owningHerdID: UUID?
    ) async throws {
        try requireOwnedKind(kind)
        guard owningHerdID == herdID else {
            throw CoreDataAnimalContractTestError.unsupportedIdentityKind
        }

        do {
            switch kind {
            case .animal:
                _ = try await makeAnimalRepository().createAnimal(
                    CreateAnimalAggregateTransaction(
                        animalID: id,
                        attributes: AnimalAggregateAttributes(
                            name: identityPayload("animal", variant: variant),
                            sex: .female,
                            birthDate: Date(timeIntervalSinceReferenceDate: 2_000),
                            status: .active,
                            pastureID: nil,
                            sireID: nil,
                            damID: nil,
                            distinguishingFeatures: [],
                            saleDate: nil,
                            salePrice: nil,
                            reasonSold: nil,
                            deathDate: nil,
                            causeOfDeath: nil,
                            statusReferenceID: nil
                        ),
                        tags: []
                    )
                )

            case .animalTag:
                let ownerID = tagOwnerID(for: variant)
                let repository = makeAnimalRepository()
                let current = try XCTUnwrap(
                    repository.fetchAnimalAggregateForEditing(id: ownerID),
                    "The AnimalTag identity fixture must retain its pre-seeded owner Animal."
                )
                _ = try await repository.updateAnimal(
                    UpdateAnimalAggregateTransaction(
                        animalID: ownerID,
                        expectedRevision: current.revision,
                        attributes: attributes(from: current.animal),
                        tags: [
                            AnimalTagTransactionState(
                                id: id,
                                number: identityPayload("tag", variant: variant),
                                colorID: nil,
                                isPrimary: false,
                                isActive: false
                            )
                        ]
                    )
                )

            default:
                throw CoreDataAnimalContractTestError.unsupportedIdentityKind
            }
        } catch let error as CoreDataPersistenceError {
            let expectedEntity: String
            switch kind {
            case .animal:
                expectedEntity = CDAnimal.coreDataEntityName
            case .animalTag:
                expectedEntity = CDAnimalTag.coreDataEntityName
            default:
                throw error
            }

            guard case let .duplicateApplicationID(entity, duplicateID, duplicateHerdID) = error,
                  entity == expectedEntity,
                  duplicateID == id,
                  duplicateHerdID == herdID else {
                throw error
            }
            throw IdentityContractSeedError.duplicateApplicationID(
                kind: kind,
                id: id,
                owningHerdID: herdID
            )
        }
    }

    func snapshotsInIdentityScope(
        for kind: IdentityContractEntityKind,
        id: UUID
    ) throws -> [IdentityContractEntitySnapshot] {
        try requireOwnedKind(kind)
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            let objects = try fetchObjects(kind: kind, id: id, context: context)
            return objects.map {
                IdentityContractEntitySnapshot(
                    id: id,
                    owningHerdID: herdID,
                    stateFingerprint: CoreDataContractStoreSnapshotter.objectFingerprint(
                        $0,
                        includeApplicationID: false
                    )
                )
            }
        }
    }

    func allEntityIDsInIdentityScope(
        for kind: IdentityContractEntityKind
    ) throws -> Set<UUID> {
        try requireOwnedKind(kind)
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            Set(
                try fetchObjects(kind: kind, id: nil, context: context)
                    .compactMap { $0.value(forKey: "id") as? UUID }
            )
        }
    }

    func supportStateSnapshot(
        for kind: IdentityContractEntityKind
    ) throws -> IdentityContractSupportStateSnapshot {
        try requireOwnedKind(kind)
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            guard let herd = try assembly.lookup.herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            var counts: [IdentityContractSupportRecordSnapshot: Int] = [:]
            let herdSnapshot = IdentityContractSupportRecordSnapshot(
                kind: .herd,
                id: herdID,
                owningHerdID: nil,
                stateFingerprint: CoreDataContractStoreSnapshotter.objectFingerprint(
                    herd,
                    includeApplicationID: false
                )
            )
            counts[herdSnapshot, default: 0] += 1

            if kind == .animalTag {
                for animalID in [originalTagOwnerID, unrelatedTagOwnerID, duplicateTagOwnerID] {
                    guard let animal = try assembly.lookup.herdOwned(
                        CDAnimal.self,
                        id: animalID,
                        herdID: herdID,
                        in: context
                    ) else {
                        throw AnimalValidationError.animalNotFound
                    }
                    let animalSnapshot = IdentityContractSupportRecordSnapshot(
                        kind: .animal,
                        id: animalID,
                        owningHerdID: herdID,
                        stateFingerprint: CoreDataContractStoreSnapshotter.objectFingerprint(
                            animal,
                            includeApplicationID: false
                        )
                    )
                    counts[animalSnapshot, default: 0] += 1
                }
            }

            return IdentityContractSupportStateSnapshot(recordCounts: counts)
        }
    }

    private func makeAnimalRepository() -> CoreDataAnimalRepository {
        let selection = CoreDataAnimalContractSelection()
        selection.currentHerdID = herdID
        return CoreDataAnimalRepository(selection: selection, assembly: assembly)
    }

    private func tagOwnerID(
        for variant: IdentityContractSeedVariant
    ) -> UUID {
        switch variant {
        case .original:
            return originalTagOwnerID
        case .unrelatedControl:
            return unrelatedTagOwnerID
        case .conflictingDuplicate:
            return duplicateTagOwnerID
        }
    }

    private func attributes(
        from detail: AnimalDetailSnapshot
    ) -> AnimalAggregateAttributes {
        AnimalAggregateAttributes(
            name: detail.name,
            sex: detail.sex,
            birthDate: detail.birthDate,
            status: detail.status,
            pastureID: detail.pastureID,
            sireID: detail.sireID,
            damID: detail.damID,
            distinguishingFeatures: detail.distinguishingFeatures,
            saleDate: detail.saleDate,
            salePrice: detail.salePrice,
            reasonSold: detail.reasonSold,
            deathDate: detail.deathDate,
            causeOfDeath: detail.causeOfDeath,
            statusReferenceID: detail.statusReferenceID
        )
    }

    private func fetchObjects(
        kind: IdentityContractEntityKind,
        id: UUID?,
        context: NSManagedObjectContext
    ) throws -> [NSManagedObject] {
        let entityName: String
        switch kind {
        case .animal:
            entityName = CDAnimal.coreDataEntityName
        case .animalTag:
            entityName = CDAnimalTag.coreDataEntityName
        default:
            throw CoreDataAnimalContractTestError.unsupportedIdentityKind
        }

        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        if let id {
            request.predicate = NSPredicate(
                format: "id == %@ AND herd.id == %@",
                id as NSUUID,
                herdID as NSUUID
            )
        } else {
            request.predicate = NSPredicate(
                format: "herd.id == %@",
                herdID as NSUUID
            )
        }
        return try context.fetch(request)
    }

    private func requireOwnedKind(
        _ requested: IdentityContractEntityKind
    ) throws {
        guard requested == kind else {
            throw CoreDataAnimalContractTestError.unsupportedIdentityKind
        }
    }

    private func identityPayload(
        _ prefix: String,
        variant: IdentityContractSeedVariant
    ) -> String {
        switch variant {
        case .original:
            return prefix + "-original"
        case .unrelatedControl:
            return prefix + "-control"
        case .conflictingDuplicate:
            return prefix + "-duplicate"
        }
    }
}

private enum CoreDataContractStoreSnapshotter {
    private static let entityNames: [IdentityContractEntityKind: String] = [
        .herd: "Herd",
        .tagColorDefinition: "TagColorDefinition",
        .animalStatusReference: "AnimalStatusReference",
        .pastureGroup: "PastureGroup",
        .pasture: "Pasture",
        .animal: "Animal",
        .animalTag: "AnimalTag",
        .movementRecord: "MovementRecord",
        .statusRecord: "StatusRecord",
        .healthRecord: "HealthRecord",
        .pregnancyCheck: "PregnancyCheck",
        .fieldCheckSession: "FieldCheckSession",
        .fieldCheckAnimalCheck: "FieldCheckAnimalCheck",
        .fieldCheckFinding: "FieldCheckFinding",
        .workingTreatmentTemplate: "WorkingTreatmentTemplate",
        .workingSession: "WorkingSession",
        .workingQueueItem: "WorkingQueueItem",
        .workingTreatmentRecord: "WorkingTreatmentRecord"
    ]

    static func snapshot(
        assembly: CoreDataPersistenceAssembly
    ) throws -> PersistenceTransactionRollbackStateSnapshot {
        let context = assembly.contextFactory.makeReadContext()
        return try context.performAndWait {
            var ids: [IdentityContractEntityKind: Set<UUID>] = [:]
            var counts: [IdentityContractEntityKind: Int] = [:]
            var rows: [String] = []

            for kind in IdentityContractEntityKind.allCases {
                guard let entityName = entityNames[kind] else {
                    continue
                }
                let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                let objects = try context.fetch(request)
                ids[kind] = Set(objects.compactMap { $0.value(forKey: "id") as? UUID })
                counts[kind] = objects.count
                rows.append(
                    contentsOf: objects.map {
                        entityName + ":" + objectFingerprint($0, includeApplicationID: true)
                    }
                )
            }

            return PersistenceTransactionRollbackStateSnapshot(
                businessStateFingerprint: rows.sorted().joined(separator: "\n"),
                applicationIDsByKind: ids,
                persistedRowCountsByKind: counts
            )
        }
    }

    static func objectFingerprint(
        _ object: NSManagedObject,
        includeApplicationID: Bool
    ) -> String {
        var parts: [String] = []

        for name in object.entity.attributesByName.keys.sorted() {
            if !includeApplicationID && name == "id" {
                continue
            }
            parts.append("a:" + name + "=" + valueFingerprint(object.value(forKey: name)))
        }

        for name in object.entity.relationshipsByName.keys.sorted() {
            let value = object.value(forKey: name)
            let relationshipIDs: [String]
            if let related = value as? NSManagedObject {
                relationshipIDs = [applicationID(of: related)]
            } else if let related = value as? NSSet {
                relationshipIDs = related.allObjects.compactMap { item in
                    guard let managed = item as? NSManagedObject else {
                        return nil
                    }
                    return applicationID(of: managed)
                }.sorted()
            } else {
                relationshipIDs = []
            }
            parts.append("r:" + name + "=[" + relationshipIDs.joined(separator: ",") + "]")
        }

        return parts.joined(separator: "|")
    }

    private static func applicationID(of object: NSManagedObject) -> String {
        (object.value(forKey: "id") as? UUID)?.uuidString ?? "nil"
    }

    private static func valueFingerprint(_ value: Any?) -> String {
        guard let value else {
            return "nil"
        }
        if let value = value as? UUID {
            return value.uuidString
        }
        if let value = value as? Date {
            return String(value.timeIntervalSinceReferenceDate)
        }
        if let value = value as? Data {
            return value.base64EncodedString()
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return String(describing: value)
    }
}
