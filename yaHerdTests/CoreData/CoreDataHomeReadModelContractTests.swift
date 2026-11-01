import CoreData
import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class CoreDataHomeReadModelContractTests: XCTestCase {
    func testMissingImportedPastureNameBlocksReadsWithoutLosingThePasture() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        let repository = CoreDataPastureRepository(
            selection: environment.selection,
            assembly: environment.assembly
        )
        let original = try repository.create(input: PastureInput(
            name: "North Pasture", acreage: 18, usableAcreage: nil, targetAcresPerHead: nil
        ))
        let context = try environment.assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let pasture = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self, id: original.id,
                herdID: try XCTUnwrap(environment.selection.currentHerdID), in: context
            ))
            pasture.name = nil
            try context.save()
        }

        XCTAssertThrowsError(try repository.fetchPastures()) {
            XCTAssertEqual($0 as? PastureValidationError, .emptyName)
        }
        XCTAssertThrowsError(try repository.fetchPastureDetail(id: original.id)) {
            XCTAssertEqual($0 as? PastureValidationError, .emptyName)
        }
        XCTAssertThrowsError(try repository.fetchPastureOptions()) {
            XCTAssertEqual($0 as? PastureValidationError, .emptyName)
        }
        XCTAssertThrowsError(try repository.nameExists("North Pasture", excluding: nil)) {
            XCTAssertEqual($0 as? PastureValidationError, .emptyName)
        }

        let readModel = CoreDataReadModelActor(
            contextFactory: environment.assembly.contextFactory,
            lookup: CoreDataLookup(),
            currentHerdID: { environment.selection.currentHerdID }
        )
        do {
            _ = try await readModel.fetchDashboardPastureRecords()
            XCTFail("Dashboard must reject an imported pasture with no name")
        } catch {
            XCTAssertEqual(error as? PastureValidationError, .emptyName)
        }
        do {
            _ = try await readModel.fetchAnimalPastureOptions(limit: 50)
            XCTFail("Animal pasture picker must reject missing names")
        } catch {
            XCTAssertEqual(error as? PastureValidationError, .emptyName)
        }

        try context.performAndWait {
            let pasture = try XCTUnwrap(CoreDataLookup().herdOwned(
                CDPasture.self, id: original.id,
                herdID: try XCTUnwrap(environment.selection.currentHerdID), in: context
            ))
            pasture.name = original.name
            try context.save()
        }
        XCTAssertEqual(try repository.fetchPastureDetail(id: original.id), original)
        XCTAssertEqual(try repository.fetchPastureOptions().first?.name, original.name)
        XCTAssertEqual(try await readModel.fetchDashboardPastureRecords().first?.name, original.name)
    }

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
            lookup: CoreDataLookup(),
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
        try marker.markPastureGrazedToday(id: grazed.id, on: grazingDate)

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
        // An unresolved collision is rejected by the global count query; a
        // resolved collision still belongs to the fetched warning-session
        // graph and must be rejected by the same Home read contract.
        for status in [FieldCheckFindingStatus.open, .resolved] {
            let environment = try await CoreDataHomeReadModelContractEnvironment.make()
            let duplicateFindingID = try environment.seedDuplicateFindingIDsAcrossSessions(
                status: status
            )
            let expectedError = CoreDataPersistenceError.duplicateApplicationID(
                entity: CDFieldCheckFinding.coreDataEntityName,
                id: duplicateFindingID,
                herdID: environment.herdID
            )
            let reader = environment.fixture.makeHomeFieldCheckQueryReader()

            await XCTAssertThrowsErrorAsync(
                try await reader.fetchHomeFieldCheckRecords()
            ) { error in
                XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
            }

            // The direct Field Check reader already rejects the complete
            // selected-Herd finding identity cohort, regardless of status.
            let direct = CoreDataFieldCheckRepository(
                selection: environment.selection,
                assembly: environment.assembly
            )
            XCTAssertThrowsError(try direct.fetchSessions()) { error in
                XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
            }

            // A separate read-only Core Data assembly must see the same
            // original physical collision without any implicit repair.
            let reopened = try await environment.makeReadOnlyAssembly()
            let reopenedReader = CoreDataReadModelActor(
                contextFactory: reopened.contextFactory,
                lookup: CoreDataLookup(),
                currentHerdID: { environment.selection.currentHerdID }
            )
            await XCTAssertThrowsErrorAsync(
                try await reopenedReader.fetchHomeFieldCheckRecords()
            ) { error in
                XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
            }

            let readContext = reopened.contextFactory.makeReadContext()
            let physicalRows = try await readContext.perform {
                let request = NSFetchRequest<CDFieldCheckFinding>(
                    entityName: CDFieldCheckFinding.coreDataEntityName
                )
                request.predicate = NSPredicate(
                    format: "id == %@",
                    duplicateFindingID as NSUUID
                )
                return try readContext.count(for: request)
            }
            XCTAssertEqual(physicalRows, 2)
        }
    }

    func testHomeFieldCheckRejectsSessionIDCollisionOutsideWarningPredicate() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        let warningID = UUID()
        let completedID = UUID()
        let controlID = UUID()
        let foreignHerdID = UUID()

        let seedContext = try environment.assembly.contextFactory.makeWriteContext()
        try seedContext.performAndWait {
            let herd = try XCTUnwrap(
                CoreDataLookup().herd(id: environment.herdID, in: seedContext)
            )
            let foreignHerd = CDHerd(context: seedContext)
            foreignHerd.id = foreignHerdID
            foreignHerd.name = "Independent Field Check Herd"
            foreignHerd.createdAt = Date(timeIntervalSinceReferenceDate: 1_100)
            foreignHerd.updatedAt = foreignHerd.createdAt

            let selectedPasture = CDPasture(context: seedContext)
            selectedPasture.id = UUID()
            selectedPasture.name = "Selected active pasture"
            selectedPasture.sortOrder = 0
            selectedPasture.herd = herd
            let foreignPasture = CDPasture(context: seedContext)
            foreignPasture.id = UUID()
            foreignPasture.name = "Independent active pasture"
            foreignPasture.sortOrder = 0
            foreignPasture.herd = foreignHerd

            let rows: [(owner: CDHerd, id: UUID, finished: Bool, note: String)] = [
                (herd, warningID, false, "selected warning"),
                (herd, completedID, true, "selected completed history"),
                (herd, controlID, true, "unrelated completed control"),
                (foreignHerd, warningID, false, "independent warning")
            ]
            for (index, row) in rows.enumerated() {
                let session = CDFieldCheckSession(context: seedContext)
                session.id = row.id
                session.startedAt = Date(timeIntervalSinceReferenceDate: 12_000 + Double(index))
                session.completedAt = row.finished
                    ? Date(timeIntervalSinceReferenceDate: 13_000 + Double(index))
                    : nil
                session.notes = row.note
                session.expectedHeadCountSnapshot = 0
                session.quickCowCount = 0
                session.quickHeiferCount = 0
                session.quickCalfCount = 0
                session.quickBullCount = 0
                session.quickSteerCount = 0
                let pasture = row.owner === herd ? selectedPasture : foreignPasture
                session.pastureIDSnapshot = pasture.id
                session.pastureNameSnapshot = pasture.name
                session.pastureArchivedAt = nil
                session.herd = row.owner
                session.pasture = pasture
            }
            try seedContext.save()
        }

        let homeReader = environment.fixture.makeHomeFieldCheckQueryReader()
        let baseline = try await homeReader.fetchHomeFieldCheckRecords()
        XCTAssertEqual(baseline.sessions.map(\.id), [warningID])
        XCTAssertEqual(baseline.openFindingCount, 0)
        XCTAssertTrue(baseline.openFindings.isEmpty)
        XCTAssertTrue(baseline.hasHistory)

        let direct = CoreDataFieldCheckRepository(
            selection: environment.selection,
            assembly: environment.assembly
        )
        XCTAssertEqual(
            Set(try direct.fetchSessions().map(\.id)),
            Set([warningID, completedID, controlID])
        )

        // Corrupt only the completed selected-Herd row. It is outside every
        // Home warning predicate but now shares the visible warning's UUID.
        let mutationContext = try environment.assembly.contextFactory.makeWriteContext()
        try mutationContext.performAndWait {
            let completed = try XCTUnwrap(
                CoreDataLookup().herdOwned(
                    CDFieldCheckSession.self,
                    id: completedID,
                    herdID: environment.herdID,
                    in: mutationContext
                )
            )
            completed.id = warningID
            try mutationContext.save()
        }

        let expectedError = CoreDataPersistenceError.duplicateApplicationID(
            entity: CDFieldCheckSession.coreDataEntityName,
            id: warningID,
            herdID: environment.herdID
        )
        await XCTAssertThrowsErrorAsync(
            try await homeReader.fetchHomeFieldCheckRecords()
        ) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }
        XCTAssertThrowsError(try direct.fetchSessions()) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }

        let reopened = try await environment.makeReadOnlyAssembly()
        let reopenedReader = CoreDataReadModelActor(
            contextFactory: reopened.contextFactory,
            lookup: CoreDataLookup(),
            currentHerdID: { environment.selection.currentHerdID }
        )
        await XCTAssertThrowsErrorAsync(
            try await reopenedReader.fetchHomeFieldCheckRecords()
        ) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }

        // Reusing a UUID in a different Herd is valid and unaffected.
        environment.selection.currentHerdID = foreignHerdID
        let foreign = try await reopenedReader.fetchHomeFieldCheckRecords()
        XCTAssertEqual(foreign.sessions.map(\.id), [warningID])
        XCTAssertEqual(foreign.openFindingCount, 0)
        XCTAssertTrue(foreign.hasHistory)
        environment.selection.currentHerdID = environment.herdID

        // Neither failed read repaired, merged or discarded a physical row.
        let readContext = reopened.contextFactory.makeReadContext()
        let physicalRows = try await readContext.perform {
            let request = NSFetchRequest<CDFieldCheckSession>(
                entityName: CDFieldCheckSession.coreDataEntityName
            )
            return try readContext.fetch(request).map {
                (herdID: $0.herd.id, id: $0.id, note: $0.notes, completed: $0.completedAt != nil)
            }
        }
        XCTAssertEqual(physicalRows.count, 4)
        XCTAssertEqual(
            physicalRows.filter { $0.herdID == environment.herdID && $0.id == warningID }.count,
            2
        )
        XCTAssertEqual(
            physicalRows.filter {
                $0.herdID == environment.herdID
                    && $0.note == "selected completed history"
                    && $0.completed
            }.count,
            1
        )
        XCTAssertEqual(
            physicalRows.filter { $0.herdID == environment.herdID && $0.id == controlID }.count,
            1
        )
        XCTAssertEqual(
            physicalRows.filter { $0.herdID == foreignHerdID && $0.id == warningID }.count,
            1
        )
    }

    func testOrphanedFieldCheckRosterFailsHomeAndDirectReadsWithoutDeletingData() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        let fixture = try environment.seedOffWarningChildIdentityFixture(kind: .animalCheck)
        let direct = CoreDataFieldCheckRepository(
            selection: environment.selection,
            assembly: environment.assembly
        )
        let home = environment.fixture.makeHomeFieldCheckQueryReader()

        let context = try environment.assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            let check = try XCTUnwrap(
                CoreDataLookup().herdOwned(
                    CDFieldCheckAnimalCheck.self,
                    id: fixture.completedChildID,
                    herdID: environment.herdID,
                    in: context
                )
            )
            check.session = nil
            try context.save()
        }

        let expected = CoreDataFieldCheckMappingError.missingAnimalCheckSession(
            checkID: fixture.completedChildID
        )
        XCTAssertThrowsError(try direct.fetchSessions()) { error in
            XCTAssertEqual(error as? CoreDataFieldCheckMappingError, expected)
        }
        await XCTAssertThrowsErrorAsync(
            try await home.fetchHomeFieldCheckRecords()
        ) { error in
            XCTAssertEqual(error as? CoreDataFieldCheckMappingError, expected)
        }

        let readContext = environment.assembly.contextFactory.makeReadContext()
        try readContext.performAndWait {
            let check = try XCTUnwrap(
                CoreDataLookup().herdOwned(
                    CDFieldCheckAnimalCheck.self,
                    id: fixture.completedChildID,
                    herdID: environment.herdID,
                    in: readContext
                )
            )
            XCTAssertNil(check.session, "A read failure must not repair or delete remote data.")
        }
    }

    func testHomeFieldCheckRejectsCrossHerdHistoricalChildSessionLinks() async throws {
        // Both relationship directions are material. Finding ownership from
        // selected child to foreign session is an existing Home safeguard;
        // the inverse finding direction and both roster-check directions
        // must also reject off-warning persisted corruption.
        for kind in FieldCheckChildIdentityKind.allCases {
            for direction in FieldCheckChildGraphDirection.allCases {
                let environment = try await CoreDataHomeReadModelContractEnvironment.make()
                let fixture = try environment.seedOffWarningChildIdentityFixture(
                    kind: kind
                )
                let home = environment.fixture.makeHomeFieldCheckQueryReader()
                let direct = CoreDataFieldCheckRepository(
                    selection: environment.selection,
                    assembly: environment.assembly
                )

                let baseline = try await home.fetchHomeFieldCheckRecords()
                XCTAssertEqual(baseline.sessions.map(\.id), [fixture.warningSessionID])
                XCTAssertEqual(baseline.openFindingCount, 0)
                XCTAssertTrue(baseline.hasHistory)
                XCTAssertEqual(
                    Set(try direct.fetchSessions().map(\.id)),
                    Set([
                        fixture.warningSessionID,
                        fixture.completedSessionID,
                        fixture.controlSessionID
                    ])
                )

                let selectedChild = direction == .selectedChildForeignSession
                let childID = selectedChild
                    ? fixture.completedChildID
                    : fixture.warningChildID
                let childHerdID = selectedChild
                    ? environment.herdID
                    : fixture.foreignHerdID
                let targetSessionID = selectedChild
                    ? fixture.foreignSessionID
                    : fixture.completedSessionID
                let targetSessionHerdID = selectedChild
                    ? fixture.foreignHerdID
                    : environment.herdID

                let mutationContext = try environment.assembly.contextFactory.makeWriteContext()
                try mutationContext.performAndWait {
                    let target = try XCTUnwrap(
                        CoreDataLookup().herdOwned(
                            CDFieldCheckSession.self,
                            id: targetSessionID,
                            herdID: targetSessionHerdID,
                            in: mutationContext
                        )
                    )
                    switch kind {
                    case .finding:
                        let finding = try XCTUnwrap(
                            CoreDataLookup().herdOwned(
                                CDFieldCheckFinding.self,
                                id: childID,
                                herdID: childHerdID,
                                in: mutationContext
                            )
                        )
                        finding.session = target
                    case .animalCheck:
                        let check = try XCTUnwrap(
                            CoreDataLookup().herdOwned(
                                CDFieldCheckAnimalCheck.self,
                                id: childID,
                                herdID: childHerdID,
                                in: mutationContext
                            )
                        )
                        check.session = target
                    }
                    try mutationContext.save()
                }

                let expectedError = selectedChild
                    ? CoreDataReadModelError.invalidHerdOwnership(
                        entity: CDFieldCheckSession.coreDataEntityName,
                        id: targetSessionID,
                        expectedHerdID: environment.herdID,
                        actualHerdID: fixture.foreignHerdID
                    )
                    : CoreDataReadModelError.invalidHerdOwnership(
                        entity: kind.entityName,
                        id: childID,
                        expectedHerdID: environment.herdID,
                        actualHerdID: fixture.foreignHerdID
                    )

                await XCTAssertThrowsErrorAsync(
                    try await home.fetchHomeFieldCheckRecords()
                ) { error in
                    XCTAssertEqual(error as? CoreDataReadModelError, expectedError)
                }
                XCTAssertThrowsError(try direct.fetchSessions()) { error in
                    XCTAssertEqual(error as? CoreDataReadModelError, expectedError)
                }

                let reopened = try await environment.makeReadOnlyAssembly()
                let reopenedHome = CoreDataReadModelActor(
                    contextFactory: reopened.contextFactory,
                    lookup: CoreDataLookup(),
                    currentHerdID: { environment.selection.currentHerdID }
                )
                await XCTAssertThrowsErrorAsync(
                    try await reopenedHome.fetchHomeFieldCheckRecords()
                ) { error in
                    XCTAssertEqual(error as? CoreDataReadModelError, expectedError)
                }

                // Failed reads cannot repair or delete the corrupted child;
                // the other selected-Herd history and warning remain intact.
                let readContext = reopened.contextFactory.makeReadContext()
                let persisted = try await readContext.perform {
                    if kind == .finding {
                        let request = NSFetchRequest<CDFieldCheckFinding>(
                            entityName: CDFieldCheckFinding.coreDataEntityName
                        )
                        return try readContext.fetch(request).map {
                            (id: $0.id, herdID: $0.herd.id, sessionID: try XCTUnwrap($0.session).id)
                        }
                    }
                    let request = NSFetchRequest<CDFieldCheckAnimalCheck>(
                        entityName: CDFieldCheckAnimalCheck.coreDataEntityName
                    )
                    return try readContext.fetch(request).map {
                        (id: $0.id, herdID: $0.herd.id, sessionID: try XCTUnwrap($0.session).id)
                    }
                }
                XCTAssertEqual(persisted.count, 4)
                XCTAssertEqual(
                    persisted.filter {
                        $0.id == childID
                            && $0.herdID == childHerdID
                            && $0.sessionID == targetSessionID
                    }.count,
                    1
                )
                XCTAssertEqual(
                    persisted.filter {
                        $0.id == fixture.controlChildID
                            && $0.herdID == environment.herdID
                            && $0.sessionID == fixture.controlSessionID
                    }.count,
                    1
                )
                XCTAssertEqual(
                    persisted.filter {
                        $0.id == fixture.warningChildID
                            && $0.herdID == environment.herdID
                            && $0.sessionID == fixture.warningSessionID
                    }.count,
                    1
                )
            }
        }
    }

    func testHomeFieldCheckRejectsChildIDCollisionsOutsideWarningSessions() async throws {
        for kind in FieldCheckChildIdentityKind.allCases {
            let environment = try await CoreDataHomeReadModelContractEnvironment.make()
            let fixture = try environment.seedOffWarningChildIdentityFixture(kind: kind)
            let homeReader = environment.fixture.makeHomeFieldCheckQueryReader()
            let direct = CoreDataFieldCheckRepository(
                selection: environment.selection,
                assembly: environment.assembly
            )

            let baseline = try await homeReader.fetchHomeFieldCheckRecords()
            XCTAssertEqual(baseline.sessions.map { $0.id }, [fixture.warningSessionID])
            XCTAssertEqual(baseline.openFindingCount, 0)
            XCTAssertTrue(baseline.openFindings.isEmpty)
            XCTAssertTrue(baseline.hasHistory)
            XCTAssertEqual(
                Set(try direct.fetchSessions().map { $0.id }),
                Set([
                    fixture.warningSessionID,
                    fixture.completedSessionID,
                    fixture.controlSessionID
                ])
            )

            // A completed, resolved child lies outside the Home warning query.
            // Give it the visible warning child's UUID without changing its
            // physical session, status, snapshots or an unrelated control row.
            try environment.duplicateCompletedChildID(
                kind: kind,
                existingID: fixture.completedChildID,
                duplicateID: fixture.warningChildID
            )
            let expectedError = CoreDataPersistenceError.duplicateApplicationID(
                entity: kind.entityName,
                id: fixture.warningChildID,
                herdID: environment.herdID
            )
            await XCTAssertThrowsErrorAsync(
                try await homeReader.fetchHomeFieldCheckRecords()
            ) { error in
                XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
            }
            XCTAssertThrowsError(try direct.fetchSessions()) { error in
                XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
            }

            // The independent read-only SQLite reopening sees the same
            // collision. Neither reader repairs or discards physical records.
            let reopened = try await environment.makeReadOnlyAssembly()
            let reopenedReader = CoreDataReadModelActor(
                contextFactory: reopened.contextFactory,
                lookup: CoreDataLookup(),
                currentHerdID: { environment.selection.currentHerdID }
            )
            await XCTAssertThrowsErrorAsync(
                try await reopenedReader.fetchHomeFieldCheckRecords()
            ) { error in
                XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
            }

            environment.selection.currentHerdID = fixture.foreignHerdID
            let foreign = try await reopenedReader.fetchHomeFieldCheckRecords()
            XCTAssertEqual(foreign.sessions.map { $0.id }, [fixture.foreignSessionID])
            XCTAssertEqual(foreign.openFindingCount, 0)
            XCTAssertTrue(foreign.hasHistory)
            environment.selection.currentHerdID = environment.herdID

            let readContext = reopened.contextFactory.makeReadContext()
            let physical = try await readContext.perform {
                if kind == .finding {
                    let request = NSFetchRequest<CDFieldCheckFinding>(
                        entityName: CDFieldCheckFinding.coreDataEntityName
                    )
                    return try readContext.fetch(request).map {
                        (herdID: $0.herd.id, id: $0.id, completed: try XCTUnwrap($0.session).completedAt != nil)
                    }
                }
                let request = NSFetchRequest<CDFieldCheckAnimalCheck>(
                    entityName: CDFieldCheckAnimalCheck.coreDataEntityName
                )
                return try readContext.fetch(request).map {
                    (herdID: $0.herd.id, id: $0.id, completed: try XCTUnwrap($0.session).completedAt != nil)
                }
            }
            XCTAssertEqual(physical.count, 4)
            XCTAssertEqual(
                physical.filter {
                    $0.herdID == environment.herdID && $0.id == fixture.warningChildID
                }.count,
                2
            )
            XCTAssertEqual(
                physical.filter {
                    $0.herdID == environment.herdID
                        && $0.id == fixture.warningChildID
                        && $0.completed
                }.count,
                1
            )
            XCTAssertEqual(
                physical.filter {
                    $0.herdID == environment.herdID && $0.id == fixture.controlChildID
                }.count,
                1
            )
            XCTAssertEqual(
                physical.filter {
                    $0.herdID == fixture.foreignHerdID && $0.id == fixture.warningChildID
                }.count,
                1
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

    func testImportedTemplateWithoutNameFailsLibraryAndHomeReadsWithoutRepairingData() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        let templates = CoreDataWorkingTreatmentTemplateRepository(
            selection: environment.selection,
            assembly: environment.assembly
        )
        let healthyID = try templates.createTemplate(name: "Healthy Template", items: [])
        let incompleteID = UUID()
        let writeContext = try environment.assembly.contextFactory.makeWriteContext()
        try writeContext.performAndWait {
            let herd = try XCTUnwrap(CoreDataLookup().herd(id: environment.herdID, in: writeContext))
            let incomplete = CDWorkingTreatmentTemplate(context: writeContext)
            incomplete.id = incompleteID
            incomplete.name = nil
            incomplete.itemsData = Data("[]".utf8)
            incomplete.herd = herd
            try writeContext.save()
        }

        let reopened = try await environment.makeReadOnlyAssembly()
        let reopenedTemplates = CoreDataWorkingTreatmentTemplateRepository(
            selection: environment.selection,
            assembly: reopened
        )
        XCTAssertEqual(
            try reopenedTemplates.fetchTemplateDetail(id: healthyID)?.name,
            "Healthy Template"
        )

        let expectedError = CoreDataWorkingMappingError.corruptTreatmentTemplate(
            templateID: incompleteID
        )
        XCTAssertThrowsError(
            try reopenedTemplates.fetchTemplateDetail(id: incompleteID)
        ) { error in
            XCTAssertEqual(error as? CoreDataWorkingMappingError, expectedError)
        }
        XCTAssertThrowsError(try reopenedTemplates.fetchTemplates()) { error in
            XCTAssertEqual(error as? CoreDataWorkingMappingError, expectedError)
        }

        let homeReader = CoreDataReadModelActor(
            contextFactory: reopened.contextFactory,
            lookup: CoreDataLookup(),
            currentHerdID: { environment.selection.currentHerdID }
        )
        await XCTAssertThrowsErrorAsync(
            try await homeReader.fetchHomeTreatmentTemplates(limit: 10)
        ) { error in
            XCTAssertEqual(error as? CoreDataWorkingMappingError, expectedError)
        }

        // An incomplete imported row must not be silently renamed while checking
        // the uniqueness of a newly created template.
        XCTAssertThrowsError(
            try templates.createTemplate(name: "New Template", items: [])
        ) { error in
            XCTAssertEqual(error as? CoreDataWorkingMappingError, expectedError)
        }

        let inspection = reopened.contextFactory.makeReadContext()
        try inspection.performAndWait {
            let request = NSFetchRequest<CDWorkingTreatmentTemplate>(
                entityName: CDWorkingTreatmentTemplate.coreDataEntityName
            )
            let saved = try inspection.fetch(request)
            XCTAssertEqual(saved.count, 2)
            XCTAssertNil(saved.first(where: { $0.id == incompleteID })?.name)
            XCTAssertEqual(saved.first(where: { $0.id == healthyID })?.name, "Healthy Template")
        }
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
            lookup: CoreDataLookup(),
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
                CoreDataLookup().herd(
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
            lookup: CoreDataLookup(),
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
                CoreDataLookup().herdOwned(
                    CDWorkingTreatmentTemplate.self,
                    id: corruptTemplateID,
                    herdID: environment.herdID,
                    in: freshContext
                )
            )
            XCTAssertEqual(corrupt.itemsData, invalidPayload)
            let healthy = try XCTUnwrap(
                CoreDataLookup().herdOwned(
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
                CoreDataLookup().herd(
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
            lookup: CoreDataLookup(),
            currentHerdID: { environment.selection.currentHerdID }
        )
        let homeTemplates = try await homeReader.fetchHomeTreatmentTemplates(limit: 10)
        XCTAssertEqual(homeTemplates, expected)
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
                CoreDataLookup().herd(
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

        // Only the first physical duplicate is inside this Home page.
        // The second has the same UUID but lies beyond the query limit.
        // The direct library and bounded Home read must agree on corruption.
        let liveHomeReader = CoreDataReadModelActor(
            contextFactory: environment.assembly.contextFactory,
            lookup: CoreDataLookup(),
            currentHerdID: { environment.selection.currentHerdID }
        )
        await XCTAssertThrowsErrorAsync(
            try await liveHomeReader.fetchHomeTreatmentTemplates(limit: 1)
        ) { error in
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
            lookup: CoreDataLookup(),
            currentHerdID: { environment.selection.currentHerdID }
        )
        await XCTAssertThrowsErrorAsync(
            try await homeReader.fetchHomeTreatmentTemplates(limit: 10)
        ) { error in
            XCTAssertEqual(error as? CoreDataPersistenceError, expectedError)
        }
        await XCTAssertThrowsErrorAsync(
            try await homeReader.fetchHomeTreatmentTemplates(limit: 1)
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

    func testHomeTemplateIdentityPreflightDetectsDuplicateAcross250RowBoundary() async throws {
        let environment = try await CoreDataHomeReadModelContractEnvironment.make()
        let selectedHerdID = environment.herdID
        let foreignHerdID = UUID()
        let firstID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let boundaryID = try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-0000000000FA")
        )

        // Exactly 250 unique selected-Herd IDs fill the first scan page.
        // The foreign Herd legally reuses the last selected-Herd identity.
        let seedContext = try environment.assembly.contextFactory.makeWriteContext()
        try seedContext.performAndWait {
            let herd = try XCTUnwrap(
                CoreDataLookup().herd(id: selectedHerdID, in: seedContext)
            )
            let foreignHerd = CDHerd(context: seedContext)
            foreignHerd.id = foreignHerdID
            foreignHerd.name = "Independent Template Herd"
            foreignHerd.createdAt = Date(timeIntervalSinceReferenceDate: 900)
            foreignHerd.updatedAt = foreignHerd.createdAt

            for index in 1...250 {
                let id = try XCTUnwrap(
                    UUID(uuidString: String(
                        format: "00000000-0000-0000-0000-%012X", index
                    ))
                )
                let template = CDWorkingTreatmentTemplate(context: seedContext)
                template.id = id
                template.name = String(format: "Template %03d", index)
                template.itemsData = Data("[]".utf8)
                template.herd = herd
            }
            let independent = CDWorkingTreatmentTemplate(context: seedContext)
            independent.id = boundaryID
            independent.name = "Foreign Herd Template"
            independent.itemsData = Data("[]".utf8)
            independent.herd = foreignHerd
            try seedContext.save()
        }

        let reader = CoreDataReadModelActor(
            contextFactory: environment.assembly.contextFactory,
            lookup: CoreDataLookup(),
            currentHerdID: { environment.selection.currentHerdID }
        )
        let firstPage = try await reader.fetchHomeTreatmentTemplates(limit: 1)
        XCTAssertEqual(
            firstPage,
            [WorkingTreatmentTemplateSummary(
                id: firstID, name: "Template 001", treatmentCount: 0
            )]
        )

        // One additional physical row shares the last ID of the first page.
        // Its duplicate must be detected on the second fetch, despite the
        // independent Home projection still requesting only one template.
        let collisionContext = try environment.assembly.contextFactory.makeWriteContext()
        try collisionContext.performAndWait {
            let herd = try XCTUnwrap(
                CoreDataLookup().herd(id: selectedHerdID, in: collisionContext)
            )
            let duplicate = CDWorkingTreatmentTemplate(context: collisionContext)
            duplicate.id = boundaryID
            duplicate.name = "Off Page Duplicate"
            duplicate.itemsData = Data("[]".utf8)
            duplicate.herd = herd
            try collisionContext.save()
        }

        let error = CoreDataPersistenceError.duplicateApplicationID(
            entity: CDWorkingTreatmentTemplate.coreDataEntityName,
            id: boundaryID,
            herdID: selectedHerdID
        )
        await XCTAssertThrowsErrorAsync(
            try await reader.fetchHomeTreatmentTemplates(limit: 1)
        ) { thrown in
            XCTAssertEqual(thrown as? CoreDataPersistenceError, error)
        }
        let direct = CoreDataWorkingTreatmentTemplateRepository(
            selection: environment.selection,
            assembly: environment.assembly
        )
        XCTAssertThrowsError(try direct.fetchTemplates()) { thrown in
            XCTAssertEqual(thrown as? CoreDataPersistenceError, error)
        }

        let reopened = try await environment.makeReadOnlyAssembly()
        let reopenedReader = CoreDataReadModelActor(
            contextFactory: reopened.contextFactory,
            lookup: CoreDataLookup(),
            currentHerdID: { environment.selection.currentHerdID }
        )
        await XCTAssertThrowsErrorAsync(
            try await reopenedReader.fetchHomeTreatmentTemplates(limit: 1)
        ) { thrown in
            XCTAssertEqual(thrown as? CoreDataPersistenceError, error)
        }

        let inspection = reopened.contextFactory.makeReadContext()
        try inspection.performAndWait {
            let herd = try XCTUnwrap(
                CoreDataLookup().herd(id: selectedHerdID, in: inspection)
            )
            let request = NSFetchRequest<CDWorkingTreatmentTemplate>(
                entityName: CDWorkingTreatmentTemplate.coreDataEntityName
            )
            request.predicate = NSPredicate(format: "herd == %@", herd)
            let physical = try inspection.fetch(request)
            XCTAssertEqual(physical.count, 251)
            XCTAssertEqual(physical.filter { $0.id == boundaryID }.count, 2)
            XCTAssertEqual(physical.filter { $0.id == firstID }.count, 1)
        }

        environment.selection.currentHerdID = foreignHerdID
        let foreignPage = try await reopenedReader.fetchHomeTreatmentTemplates(limit: 1)
        XCTAssertEqual(
            foreignPage,
            [WorkingTreatmentTemplateSummary(
                id: boundaryID, name: "Foreign Herd Template", treatmentCount: 0
            )]
        )
        environment.selection.currentHerdID = selectedHerdID
    }
}

private enum FieldCheckChildGraphDirection: CaseIterable, Sendable {
    case selectedChildForeignSession
    case foreignChildSelectedSession
}

private enum FieldCheckChildIdentityKind: CaseIterable, Sendable {
    case finding
    case animalCheck

    var entityName: String {
        switch self {
        case .finding: return CDFieldCheckFinding.coreDataEntityName
        case .animalCheck: return CDFieldCheckAnimalCheck.coreDataEntityName
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
                    lookup: CoreDataLookup(),
                    currentHerdID: { self.selection.currentHerdID }
                )
            },
            makeHomeWorkingQueryReader: {
                CoreDataReadModelActor(
                    contextFactory: self.assembly.contextFactory,
                    lookup: CoreDataLookup(),
                    currentHerdID: { self.selection.currentHerdID }
                )
            }
        )
    }

    func seedOffWarningChildIdentityFixture(
        kind: FieldCheckChildIdentityKind
    ) throws -> (
        warningSessionID: UUID,
        completedSessionID: UUID,
        controlSessionID: UUID,
        foreignSessionID: UUID,
        foreignHerdID: UUID,
        warningChildID: UUID,
        completedChildID: UUID,
        controlChildID: UUID
    ) {
        let warningSessionID = UUID()
        let completedSessionID = UUID()
        let controlSessionID = UUID()
        let foreignSessionID = UUID()
        let foreignHerdID = UUID()
        let warningChildID = UUID()
        let completedChildID = UUID()
        let controlChildID = UUID()
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            guard let herd = try CoreDataLookup().herd(id: herdID, in: context) else {
                throw HerdRepositoryError.missingHerd
            }
            let foreignHerd = CDHerd(context: context)
            foreignHerd.id = foreignHerdID
            foreignHerd.name = "Independent Child Identity Herd"
            foreignHerd.createdAt = Date(timeIntervalSinceReferenceDate: 1_100)
            foreignHerd.updatedAt = foreignHerd.createdAt

            let selectedPasture = CDPasture(context: context)
            selectedPasture.id = UUID()
            selectedPasture.name = "Selected active pasture"
            selectedPasture.sortOrder = 0
            selectedPasture.herd = herd
            let foreignPasture = CDPasture(context: context)
            foreignPasture.id = UUID()
            foreignPasture.name = "Independent active pasture"
            foreignPasture.sortOrder = 0
            foreignPasture.herd = foreignHerd

            let rows: [(owner: CDHerd, sessionID: UUID, childID: UUID, completed: Bool)] = [
                (herd, warningSessionID, warningChildID, false),
                (herd, completedSessionID, completedChildID, true),
                (herd, controlSessionID, controlChildID, true),
                (foreignHerd, foreignSessionID, warningChildID, false)
            ]
            for (index, row) in rows.enumerated() {
                let session = CDFieldCheckSession(context: context)
                session.id = row.sessionID
                session.startedAt = Date(timeIntervalSinceReferenceDate: 12_000 + Double(index))
                session.completedAt = row.completed
                    ? Date(timeIntervalSinceReferenceDate: 13_000 + Double(index))
                    : nil
                session.notes = "Child identity fixture " + String(index)
                session.expectedHeadCountSnapshot = 0
                session.quickCowCount = 0
                session.quickHeiferCount = 0
                session.quickCalfCount = 0
                session.quickBullCount = 0
                session.quickSteerCount = 0
                let pasture = row.owner === herd ? selectedPasture : foreignPasture
                session.pastureIDSnapshot = pasture.id
                session.pastureNameSnapshot = pasture.name
                session.pastureArchivedAt = nil
                session.herd = row.owner
                session.pasture = pasture

                switch kind {
                case .finding:
                    let finding = CDFieldCheckFinding(context: context)
                    finding.id = row.childID
                    finding.recordedAt = Date(
                        timeIntervalSinceReferenceDate: 14_000 + Double(index)
                    )
                    finding.typeRawValue = FieldCheckFindingType.generalObservation.rawValue
                    finding.severityRawValue = FieldCheckFindingSeverity.info.rawValue
                    finding.statusRawValue = FieldCheckFindingStatus.resolved.rawValue
                    finding.note = "Resolved historical finding"
                    finding.animalIDSnapshot = nil
                    finding.animalDisplayTagNumberSnapshot = nil
                    finding.animalDisplayTagColorIDSnapshot = nil
                    finding.animalNameSnapshot = nil
                    finding.pastureNameSnapshot = session.pastureNameSnapshot
                    finding.herd = row.owner
                    finding.session = session
                    finding.animal = nil
                case .animalCheck:
                    let check = CDFieldCheckAnimalCheck(context: context)
                    check.id = row.childID
                    check.animalIDSnapshot = UUID()
                    check.rosterTagNumberSnapshot = "CHILD-" + String(index)
                    check.rosterTagColorIDSnapshot = nil
                    check.damRosterTagNumberSnapshot = nil
                    check.damRosterTagColorIDSnapshot = nil
                    check.animalNameSnapshot = "Historical animal"
                    check.animalSexRawValueSnapshot = Sex.female.rawValue
                    check.animalTypeRawValueSnapshot = AnimalType.cow.rawValue
                    check.wasExpectedAtStart = true
                    check.countedAt = nil
                    check.missingConfirmedAt = nil
                    check.herd = row.owner
                    check.session = session
                    check.animal = nil
                }
            }
            try context.save()
        }
        return (
            warningSessionID,
            completedSessionID,
            controlSessionID,
            foreignSessionID,
            foreignHerdID,
            warningChildID,
            completedChildID,
            controlChildID
        )
    }

    func duplicateCompletedChildID(
        kind: FieldCheckChildIdentityKind,
        existingID: UUID,
        duplicateID: UUID
    ) throws {
        let context = try assembly.contextFactory.makeWriteContext()
        try context.performAndWait {
            switch kind {
            case .finding:
                guard let finding = try CoreDataLookup().herdOwned(
                    CDFieldCheckFinding.self,
                    id: existingID,
                    herdID: herdID,
                    in: context
                ) else {
                    throw FieldCheckRepositoryError.findingNotFound
                }
                finding.id = duplicateID
            case .animalCheck:
                guard let check = try CoreDataLookup().herdOwned(
                    CDFieldCheckAnimalCheck.self,
                    id: existingID,
                    herdID: herdID,
                    in: context
                ) else {
                    throw FieldCheckRepositoryError.animalCheckNotFound
                }
                check.id = duplicateID
            }
            try context.save()
        }
    }

    func seedDuplicateAnimalCheckIDsAcrossWarningSessions() throws -> UUID {
        let duplicateCheckID = UUID()
        let context = try assembly.contextFactory.makeWriteContext()

        return try context.performAndWait {
            guard let herd = try CoreDataLookup().herd(id: herdID, in: context) else {
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

    func seedDuplicateFindingIDsAcrossSessions(
        status: FieldCheckFindingStatus
    ) throws -> UUID {
        let duplicateFindingID = UUID()
        let context = try assembly.contextFactory.makeWriteContext()

        return try context.performAndWait {
            guard let herd = try CoreDataLookup().herd(id: herdID, in: context) else {
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
                finding.statusRawValue = status.rawValue
                finding.note = "Duplicate finding with status: \(status.rawValue)"
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
