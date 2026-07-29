from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    content = file_path.read_text()
    count = content.count(old)
    if count != 1:
        raise SystemExit(f"Expected exactly one match in {path}, found {count}")
    file_path.write_text(content.replace(old, new, 1))


repository_path = "yaHerd/Data/Repositories/SwiftDataWorkingRepository.swift"
replace_once(
    repository_path,
    """            if animal.activeWorkingSession?.publicID == session.publicID
                || animal.location == .workingPen
            {
""",
    """            let activeSessionID = animal.activeWorkingSession?.publicID
            if activeSessionID == session.publicID
                || (activeSessionID == nil && animal.location == .workingPen)
            {
""",
)
replace_once(
    repository_path,
    """        guard Set(destinationsByQueueItemID.keys) == queueItemIDs else {
            throw WorkingRepositoryError.assignmentSetDoesNotMatchSession
        }

        for item in session.queueItems {
""",
    """        guard Set(destinationsByQueueItemID.keys) == queueItemIDs else {
            throw WorkingRepositoryError.assignmentSetDoesNotMatchSession
        }

        try validateCompletionOwnership(for: session)

        for item in session.queueItems {
""",
)
replace_once(
    repository_path,
    """    private func fetchActiveSession(id: UUID) throws -> WorkingSession {
""",
    """    private func validateCompletionOwnership(for session: WorkingSession) throws {
        let hasConflictingOwnership = session.queueItems.contains { item in
            guard let activeSessionID = item.animal?.activeWorkingSession?.publicID else {
                return false
            }
            return activeSessionID != session.publicID
        }

        guard !hasConflictingOwnership else {
            throw WorkingRepositoryError.animalAlreadyInAnotherSession
        }
    }

    private func fetchActiveSession(id: UUID) throws -> WorkingSession {
""",
)

tests_path = "yaHerdTests/SwiftDataWorkingSessionLifecycleTests.swift"
replace_once(
    tests_path,
    """    func testReopenRejectsAlreadyActiveSession() throws {
""",
    """    func testReopenedSessionCannotFinishAnimalOwnedByNewerActiveSession() throws {
        let fixture = try makeFinishedSessionFixture()
        try fixture.repository.reopenSession(id: fixture.session.publicID)

        let alternatePasture = Pasture(name: "South")
        fixture.repository.context.insert(alternatePasture)
        try fixture.repository.context.save()

        let newerSessionID = try fixture.repository.startSession(
            input: WorkingSessionStartInput(
                date: .now,
                sourcePastureID: fixture.sourcePasture.publicID,
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: [fixture.animal.publicID]
            )
        )
        let newerSession = try XCTUnwrap(
            fixture.repository.context.fetch(FetchDescriptor<WorkingSession>())
                .first { $0.publicID == newerSessionID }
        )
        let movementCountBefore = try fixture.repository.context.fetch(
            FetchDescriptor<MovementRecord>()
        ).count

        XCTAssertThrowsError(
            try fixture.repository.completeSession(
                id: fixture.session.publicID,
                assignments: [
                    WorkingQueueDestinationAssignment(
                        queueItemID: fixture.queueItem.publicID,
                        destinationPastureID: alternatePasture.publicID
                    )
                ]
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkingRepositoryError,
                .animalAlreadyInAnotherSession
            )
        }

        XCTAssertEqual(fixture.session.status, .active)
        XCTAssertEqual(newerSession.status, .active)
        XCTAssertEqual(fixture.animal.activeWorkingSession?.publicID, newerSessionID)
        XCTAssertEqual(fixture.animal.location, .workingPen)
        XCTAssertNil(fixture.animal.pasture)
        XCTAssertEqual(
            fixture.queueItem.destinationPasture?.publicID,
            fixture.sourcePasture.publicID
        )
        XCTAssertEqual(
            try fixture.repository.context.fetch(FetchDescriptor<MovementRecord>()).count,
            movementCountBefore
        )
    }

    func testDeletingReopenedSessionDoesNotReleaseAnimalOwnedByNewerActiveSession() throws {
        let fixture = try makeFinishedSessionFixture()
        try fixture.repository.reopenSession(id: fixture.session.publicID)

        let newerSessionID = try fixture.repository.startSession(
            input: WorkingSessionStartInput(
                date: .now,
                sourcePastureID: fixture.sourcePasture.publicID,
                treatmentTemplateName: nil,
                plannedTreatments: [],
                animalIDs: [fixture.animal.publicID]
            )
        )

        try fixture.repository.deleteSession(id: fixture.session.publicID)

        let remainingSessions = try fixture.repository.context.fetch(
            FetchDescriptor<WorkingSession>()
        )
        XCTAssertFalse(remainingSessions.contains { $0.publicID == fixture.session.publicID })
        XCTAssertTrue(remainingSessions.contains { $0.publicID == newerSessionID })
        XCTAssertEqual(fixture.animal.activeWorkingSession?.publicID, newerSessionID)
        XCTAssertEqual(fixture.animal.location, .workingPen)
        XCTAssertNil(fixture.animal.pasture)
    }

    func testReopenRejectsAlreadyActiveSession() throws {
""",
)
