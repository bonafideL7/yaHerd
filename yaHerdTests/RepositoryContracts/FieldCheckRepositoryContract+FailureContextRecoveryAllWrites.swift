import Foundation
import XCTest
@testable import yaHerd

/// Permanent same-context recovery coverage for every distinct Field Check fault-injection hook.
///
/// Each save closure must mutate the supplied probe session's notes and save through the exact write
/// context that just staged the corresponding failed operation. It must not call `rollback()`,
/// `reset()`, recreate the context, or otherwise discard pending changes first. The existing rollback
/// contracts then perform their normal raw/fresh-context assertions only after this successful save has
/// had an opportunity to flush any leaked staged state.
@MainActor
struct FieldCheckAllFailureContextsRecoveryInjection {
    let missingFinding: FieldCheckMissingFindingRollbackContextRecoveryInjection

    let sessionCreation: FieldCheckSessionCreationRollbackFailureInjection
    let saveProbeAfterSessionCreationFailure: (_ probeSessionID: UUID, _ notes: String) throws -> Void

    let trackedAnimal: FieldCheckTrackedAnimalRollbackFailureInjection
    let saveProbeAfterTrackedAnimalFailure: (_ probeSessionID: UUID, _ notes: String) throws -> Void

    let sessionCompletion: FieldCheckSessionCompletionRollbackFailureInjection
    let saveProbeAfterSessionCompletionFailure: (_ probeSessionID: UUID, _ notes: String) throws -> Void

    let rosterState: FieldCheckRosterStateRollbackFailureInjection
    let saveProbeAfterRosterMissingFailure: (_ probeSessionID: UUID, _ notes: String) throws -> Void
    let saveProbeAfterRosterCountedFailure: (_ probeSessionID: UUID, _ notes: String) throws -> Void

    let missingFindingQuickCount: FieldCheckMissingFindingQuickCountRollbackFailureInjection
    let saveProbeAfterMissingFindingQuickCountAddFailure: (_ probeSessionID: UUID, _ notes: String) throws -> Void

    let missingFindingMutationQuickCount: FieldCheckMissingFindingMutationQuickCountRollbackFailureInjection
    let saveProbeAfterMissingFindingQuickCountUpdateFailure: (_ probeSessionID: UUID, _ notes: String) throws -> Void
    let saveProbeAfterMissingFindingQuickCountStatusFailure: (_ probeSessionID: UUID, _ notes: String) throws -> Void
}

@MainActor
extension FieldCheckRepositoryContract {
    static func assertAllFaultInjectedWriteContextsRecoverBeforeNextSave(
        using fixture: FieldCheckRepositoryContractFixture,
        failureInjection: FieldCheckAllFailureContextsRecoveryInjection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let probePasture = try fixture.makePastureRepository().create(
            input: PastureInput(
                name: "All Failure Context Recovery Probe",
                acreage: 20,
                usableAcreage: 18,
                targetAcresPerHead: 1.5
            )
        )
        _ = try fixture.makeAnimalRepository().create(
            input: allFailureContextsProbeAnimalInput(pastureID: probePasture.id)
        )
        let probeSessionID = try fixture.makeFieldCheckRepository().createSession(
            input: FieldCheckSessionStartInput(
                pastureID: probePasture.id,
                startedAt: allFailureContextsRecoveryDate(year: 2026, month: 9, day: 30, hour: 8),
                notes: "All failure-context recovery probe"
            )
        )

        try assertMissingFindingFailureContextRecovers(
            using: fixture,
            failureInjection: failureInjection.missingFinding,
            file: file,
            line: line
        )

        let sessionCreation = FieldCheckSessionCreationRollbackFailureInjection(
            createSessionFailingAfterSessionStaged: { input in
                try runWithFailureContextRecoveryProbe(
                    probeSessionID: probeSessionID,
                    notes: "Probe after session creation failure",
                    saveProbe: failureInjection.saveProbeAfterSessionCreationFailure,
                    using: fixture,
                    file: file,
                    line: line
                ) {
                    try failureInjection.sessionCreation.createSessionFailingAfterSessionStaged(input)
                }
            },
            persistedAnimalCheckIDs: failureInjection.sessionCreation.persistedAnimalCheckIDs
        )
        try assertSessionCreationFailureRollsBack(
            using: fixture,
            failureInjection: sessionCreation,
            file: file,
            line: line
        )

        let trackedAnimal = FieldCheckTrackedAnimalRollbackFailureInjection(
            addTrackedAnimalFailingAfterMovementStaged: { sessionID, animalID, checkedAt in
                try runWithFailureContextRecoveryProbe(
                    probeSessionID: probeSessionID,
                    notes: "Probe after tracked-animal failure",
                    saveProbe: failureInjection.saveProbeAfterTrackedAnimalFailure,
                    using: fixture,
                    file: file,
                    line: line
                ) {
                    try failureInjection.trackedAnimal.addTrackedAnimalFailingAfterMovementStaged(
                        sessionID,
                        animalID,
                        checkedAt
                    )
                }
            }
        )
        try assertTrackedAnimalInsertionFailureRollsBack(
            using: fixture,
            failureInjection: trackedAnimal,
            file: file,
            line: line
        )

        let sessionCompletion = FieldCheckSessionCompletionRollbackFailureInjection(
            seedRawQuickCowCount: failureInjection.sessionCompletion.seedRawQuickCowCount,
            rawQuickCowCount: failureInjection.sessionCompletion.rawQuickCowCount,
            completeSessionFailingAfterCompletionStaged: { sessionID in
                try runWithFailureContextRecoveryProbe(
                    probeSessionID: probeSessionID,
                    notes: "Probe after session completion failure",
                    saveProbe: failureInjection.saveProbeAfterSessionCompletionFailure,
                    using: fixture,
                    file: file,
                    line: line
                ) {
                    try failureInjection.sessionCompletion.completeSessionFailingAfterCompletionStaged(sessionID)
                }
            }
        )
        try assertSessionCompletionFailureRollsBack(
            using: fixture,
            failureInjection: sessionCompletion,
            file: file,
            line: line
        )

        let rosterState = FieldCheckRosterStateRollbackFailureInjection(
            seedRawQuickCowCount: failureInjection.rosterState.seedRawQuickCowCount,
            rawQuickCowCount: failureInjection.rosterState.rawQuickCowCount,
            setAnimalCheckMissingFailingAfterRosterStateAndNormalizationStaged: { sessionID, animalCheckID, isMissing in
                try runWithFailureContextRecoveryProbe(
                    probeSessionID: probeSessionID,
                    notes: "Probe after roster missing failure",
                    saveProbe: failureInjection.saveProbeAfterRosterMissingFailure,
                    using: fixture,
                    file: file,
                    line: line
                ) {
                    try failureInjection.rosterState.setAnimalCheckMissingFailingAfterRosterStateAndNormalizationStaged(
                        sessionID,
                        animalCheckID,
                        isMissing
                    )
                }
            },
            setAnimalCheckCountedFailingAfterRosterStateAndNormalizationStaged: { sessionID, animalCheckID, isCounted in
                try runWithFailureContextRecoveryProbe(
                    probeSessionID: probeSessionID,
                    notes: "Probe after roster counted failure",
                    saveProbe: failureInjection.saveProbeAfterRosterCountedFailure,
                    using: fixture,
                    file: file,
                    line: line
                ) {
                    try failureInjection.rosterState.setAnimalCheckCountedFailingAfterRosterStateAndNormalizationStaged(
                        sessionID,
                        animalCheckID,
                        isCounted
                    )
                }
            }
        )
        try assertRosterMissingStateNormalizationFailureRollsBack(
            using: fixture,
            failureInjection: rosterState,
            file: file,
            line: line
        )
        try assertRosterCountedStateNormalizationFailureRollsBack(
            using: fixture,
            failureInjection: rosterState,
            file: file,
            line: line
        )

        let missingFindingQuickCount = FieldCheckMissingFindingQuickCountRollbackFailureInjection(
            rawQuickCowCount: failureInjection.missingFindingQuickCount.rawQuickCowCount,
            addMissingFindingFailingAfterMissingStateAndQuickCountNormalizationStaged: { sessionID, input in
                try runWithFailureContextRecoveryProbe(
                    probeSessionID: probeSessionID,
                    notes: "Probe after missing-finding quick-count add failure",
                    saveProbe: failureInjection.saveProbeAfterMissingFindingQuickCountAddFailure,
                    using: fixture,
                    file: file,
                    line: line
                ) {
                    try failureInjection.missingFindingQuickCount.addMissingFindingFailingAfterMissingStateAndQuickCountNormalizationStaged(
                        sessionID,
                        input
                    )
                }
            }
        )
        try assertMissingFindingQuickCountNormalizationFailureRollsBack(
            using: fixture,
            failureInjection: missingFindingQuickCount,
            file: file,
            line: line
        )

        let missingFindingMutationQuickCount = FieldCheckMissingFindingMutationQuickCountRollbackFailureInjection(
            rawQuickCowCount: failureInjection.missingFindingMutationQuickCount.rawQuickCowCount,
            updateFindingFailingAfterMissingStateAndQuickCountNormalizationStaged: { sessionID, findingID, input in
                try runWithFailureContextRecoveryProbe(
                    probeSessionID: probeSessionID,
                    notes: "Probe after missing-finding quick-count update failure",
                    saveProbe: failureInjection.saveProbeAfterMissingFindingQuickCountUpdateFailure,
                    using: fixture,
                    file: file,
                    line: line
                ) {
                    try failureInjection.missingFindingMutationQuickCount.updateFindingFailingAfterMissingStateAndQuickCountNormalizationStaged(
                        sessionID,
                        findingID,
                        input
                    )
                }
            },
            updateFindingStatusFailingAfterMissingStateAndQuickCountNormalizationStaged: { sessionID, findingID, status in
                try runWithFailureContextRecoveryProbe(
                    probeSessionID: probeSessionID,
                    notes: "Probe after missing-finding quick-count status failure",
                    saveProbe: failureInjection.saveProbeAfterMissingFindingQuickCountStatusFailure,
                    using: fixture,
                    file: file,
                    line: line
                ) {
                    try failureInjection.missingFindingMutationQuickCount.updateFindingStatusFailingAfterMissingStateAndQuickCountNormalizationStaged(
                        sessionID,
                        findingID,
                        status
                    )
                }
            }
        )
        try assertMissingFindingUpdateAndStatusQuickCountNormalizationFailuresRollBack(
            using: fixture,
            failureInjection: missingFindingMutationQuickCount,
            file: file,
            line: line
        )
    }

    private static func runWithFailureContextRecoveryProbe(
        probeSessionID: UUID,
        notes: String,
        saveProbe: (_ probeSessionID: UUID, _ notes: String) throws -> Void,
        using fixture: FieldCheckRepositoryContractFixture,
        file: StaticString,
        line: UInt,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
        } catch {
            let injectedError = error
            try saveProbe(probeSessionID, notes)

            let probeDetail = try XCTUnwrap(
                fixture.makeFieldCheckRepository().fetchSessionDetail(id: probeSessionID),
                "The recovery probe session must remain readable after the same-context save.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                probeDetail.notes,
                notes,
                "The recovery hook must perform an observable successful save through the exact context that staged the failed operation.",
                file: file,
                line: line
            )

            throw injectedError
        }
    }

    private static func allFailureContextsProbeAnimalInput(pastureID: UUID) -> AnimalInput {
        AnimalInput(
            name: "All Failure Context Recovery Animal",
            tagNumber: "FCR900",
            tagColorID: nil,
            sex: .female,
            birthDate: allFailureContextsRecoveryDate(year: 2020, month: 1, day: 1),
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

    private static func allFailureContextsRecoveryDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return components.date!
    }
}
