import Foundation
import XCTest
@testable import yaHerd

/// Every throwing application mutation currently exposed through the mutation-publishing repository boundary.
///
/// The inventory is intentionally method-level rather than feature-level. A Core Data cutover must not preserve
/// publication semantics for one representative Animal or Working command while accidentally omitting another
/// mutation entry point from the post-commit boundary.
enum MutationBoundaryContractOperation: String, CaseIterable, Sendable {
    case herdRenameCurrent

    case animalCreate
    case animalUpdate
    case animalDelete
    case animalArchive
    case animalRestore
    case animalMove
    case animalAddTag
    case animalUpdateTag
    case animalPromoteTag
    case animalRetireTag
    case animalAddHealthRecord
    case animalAddPregnancyCheck

    case pastureCreate
    case pastureUpdate
    case pastureReorder
    case pastureDelete
    case pastureCreateGroup
    case pastureUpdateGroup
    case pastureDeleteGroups
    case pastureAssignToGroup

    case dashboardMarkPastureGrazedToday

    case fieldCheckArchiveSessionsForDeletedPastures
    case fieldCheckCreateSession
    case fieldCheckUpdateQuickAnimalTypeCounts
    case fieldCheckUpdateNotes
    case fieldCheckSetAnimalCheckCounted
    case fieldCheckSetAnimalCheckMissing
    case fieldCheckAddTrackedAnimalToSession
    case fieldCheckAddFinding
    case fieldCheckUpdateFinding
    case fieldCheckUpdateFindingStatus
    case fieldCheckDeleteFinding
    case fieldCheckCompleteSession
    case fieldCheckReopenSession

    case tagColorUpsert
    case tagColorSetDefault
    case tagColorDelete
    case tagColorReorder
    case tagColorRestoreDefaults

    case workingStartSession
    case workingReopenSession
    case workingUpdateSessionTreatments
    case workingReplacePrimaryTag
    case workingCollectAnimals
    case workingCompleteQueueItem
    case workingSaveQueueItemEdits
    case workingDeleteQueueItemWorkData
    case workingDeleteSession
    case workingCompleteSession
    case workingCreateTemplate
    case workingUpdateTemplate
    case workingDeleteTemplates

    var expectedReason: DataMutationReason {
        switch self {
        case .herdRenameCurrent:
            return .herd

        case .animalCreate,
             .animalUpdate,
             .animalDelete,
             .animalArchive,
             .animalRestore,
             .animalMove,
             .animalAddTag,
             .animalUpdateTag,
             .animalPromoteTag,
             .animalRetireTag,
             .animalAddHealthRecord,
             .animalAddPregnancyCheck:
            return .animal

        case .pastureCreate,
             .pastureUpdate,
             .pastureReorder,
             .pastureDelete,
             .pastureCreateGroup,
             .pastureUpdateGroup,
             .pastureDeleteGroups,
             .pastureAssignToGroup:
            return .pasture

        case .dashboardMarkPastureGrazedToday:
            return .dashboard

        case .fieldCheckArchiveSessionsForDeletedPastures,
             .fieldCheckCreateSession,
             .fieldCheckUpdateQuickAnimalTypeCounts,
             .fieldCheckUpdateNotes,
             .fieldCheckSetAnimalCheckCounted,
             .fieldCheckSetAnimalCheckMissing,
             .fieldCheckAddTrackedAnimalToSession,
             .fieldCheckAddFinding,
             .fieldCheckUpdateFinding,
             .fieldCheckUpdateFindingStatus,
             .fieldCheckDeleteFinding,
             .fieldCheckCompleteSession,
             .fieldCheckReopenSession:
            return .fieldCheck

        case .tagColorUpsert,
             .tagColorSetDefault,
             .tagColorDelete,
             .tagColorReorder,
             .tagColorRestoreDefaults:
            return .tagColor

        case .workingStartSession,
             .workingReopenSession,
             .workingUpdateSessionTreatments,
             .workingReplacePrimaryTag,
             .workingCollectAnimals,
             .workingCompleteQueueItem,
             .workingSaveQueueItemEdits,
             .workingDeleteQueueItemWorkData,
             .workingDeleteSession,
             .workingCompleteSession,
             .workingCreateTemplate,
             .workingUpdateTemplate,
             .workingDeleteTemplates:
            return .working
        }
    }
}

/// One observation captured at the exact instant the application success recorder is invoked.
///
/// `durableStateFingerprintAtPublication` must be read from committed backing persistence through a fresh access
/// scope that cannot see unsaved/staged changes from the mutation context. That makes equality with the final durable
/// fingerprint meaningful evidence that publication happened after commit rather than merely after in-memory mutation.
struct MutationBoundaryContractPublication: Equatable, Sendable {
    let reason: DataMutationReason
    let durableStateFingerprintAtPublication: String
}

/// Target-runner control for the cross-cutting application mutation boundary.
///
/// The concrete Core Data runner prepares a valid, isolated scenario for exactly one `operation`. Fixture setup must
/// not remain in `publications`; clear any setup traffic before returning the control.
///
/// Success probes must execute the real public repository/transaction entry point represented by `operation` and make
/// a durable business-state change. Failure probes must execute that same entry point with valid Domain input but
/// inject a persistence failure after the write reaches persistence and before commit completes. A validation-only
/// failure is not sufficient for the failure probe.
///
/// `durableStateFingerprint()` must be persistence-neutral and deterministic. It must describe the durable business
/// state affected by the operation and be read from committed backing storage through a fresh access scope; it must
/// not include managed-object IDs, context identity, temporary IDs, or other persistence-framework artifacts.
@MainActor
protocol MutationBoundaryContractTestControl {
    var operation: MutationBoundaryContractOperation { get }
    var publications: [MutationBoundaryContractPublication] { get }

    func durableStateFingerprint() throws -> String
    func performSuccessfulMutation() throws
    func performFailingMutation() throws
}

/// Permanent fixture for mutation publication semantics.
///
/// Each call must create a fresh isolated scenario so the success and failure probes cannot affect one another.
@MainActor
struct MutationBoundaryContractFixture {
    let makeTestControl: (
        _ operation: MutationBoundaryContractOperation
    ) throws -> any MutationBoundaryContractTestControl
}

/// Permanent persistence-neutral contract for the application mutation boundary.
///
/// Ownership boundaries:
/// - Feature repository/transaction contracts own the detailed durable success state, validation behavior, atomic
///   rollback, relationship/history semantics, and error identities for their operations.
/// - This contract owns the cross-cutting publication invariant: one successful logical mutation publishes exactly
///   once, only after its durable commit is observable; a failed persistence mutation publishes no success event.
/// - `ApplicationMutationCenter` owns downstream invalidation sequencing and feature-area routing. Those application
///   routing details are intentionally not duplicated as persistence behavior here.
/// - `MutationPublishingSampleDataSeeder` is intentionally excluded. Its current `...IfNeeded()` API is nonthrowing
///   and may be a no-op, so it cannot expose the persistence-failure boundary required by this contract. If production
///   bootstrap gains a throwing transaction boundary, that boundary should receive its own contract instead of
///   freezing today's nonthrowing seeder behavior into the Core Data design.
@MainActor
enum MutationBoundaryContract {
    static func assertSuccessfulLogicalWritesPublishExactlyOnceAfterDurableCommit(
        using fixture: MutationBoundaryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for operation in MutationBoundaryContractOperation.allCases {
            let control = try fixture.makeTestControl(operation)
            XCTAssertEqual(
                control.operation,
                operation,
                "Mutation-boundary fixture returned the wrong prepared operation.",
                file: file,
                line: line
            )
            XCTAssertTrue(
                control.publications.isEmpty,
                "Fixture setup for \(operation.rawValue) must not leak mutation publications into the probe.",
                file: file,
                line: line
            )

            let before = try control.durableStateFingerprint()
            try control.performSuccessfulMutation()
            let after = try control.durableStateFingerprint()

            XCTAssertNotEqual(
                after,
                before,
                "The success probe for \(operation.rawValue) must perform an observable durable state change.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                control.publications.count,
                1,
                "One successful logical \(operation.rawValue) mutation must publish exactly one success event; internal child writes or saves must not publish independently.",
                file: file,
                line: line
            )

            let publication = try XCTUnwrap(control.publications.first, file: file, line: line)
            XCTAssertEqual(
                publication.reason,
                operation.expectedReason,
                "\(operation.rawValue) published the wrong application mutation reason.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                publication.durableStateFingerprintAtPublication,
                after,
                "\(operation.rawValue) must publish only after the committed durable state is observable from a fresh persistence access scope.",
                file: file,
                line: line
            )
        }
    }

    static func assertFailedPersistenceWritesPublishNothingAndDoNotCommit(
        using fixture: MutationBoundaryContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for operation in MutationBoundaryContractOperation.allCases {
            let control = try fixture.makeTestControl(operation)
            XCTAssertEqual(
                control.operation,
                operation,
                "Mutation-boundary fixture returned the wrong prepared operation.",
                file: file,
                line: line
            )
            XCTAssertTrue(
                control.publications.isEmpty,
                "Fixture setup for \(operation.rawValue) must not leak mutation publications into the probe.",
                file: file,
                line: line
            )

            let before = try control.durableStateFingerprint()
            XCTAssertThrowsError(
                try control.performFailingMutation(),
                "The failure probe for \(operation.rawValue) must surface its injected persistence failure.",
                file: file,
                line: line
            )
            let after = try control.durableStateFingerprint()

            XCTAssertEqual(
                after,
                before,
                "A failed \(operation.rawValue) persistence operation must not commit a durable state change.",
                file: file,
                line: line
            )
            XCTAssertTrue(
                control.publications.isEmpty,
                "A failed \(operation.rawValue) persistence operation must not publish a successful mutation event.",
                file: file,
                line: line
            )
        }
    }
}
