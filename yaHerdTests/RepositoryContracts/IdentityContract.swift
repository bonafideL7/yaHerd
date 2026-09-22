import Foundation
import XCTest
@testable import yaHerd

/// Independently persisted entity kinds in the production persistence graph.
///
/// The identity contract intentionally covers every durable entity because application UUID
/// uniqueness is a cross-cutting persistence invariant, not a feature-specific behavior.
enum IdentityContractEntityKind: String, CaseIterable, Sendable {
    case herd
    case tagColorDefinition
    case animalStatusReference
    case pastureGroup
    case pasture
    case animal
    case animalTag
    case movementRecord
    case statusRecord
    case healthRecord
    case pregnancyCheck
    case fieldCheckSession
    case fieldCheckAnimalCheck
    case fieldCheckFinding
    case workingTreatmentTemplate
    case workingSession
    case workingQueueItem
    case workingTreatmentRecord
}

/// Valid payload variants used by the target runner when probing duplicate application IDs.
///
/// `.original` and `.unrelatedControl` must both create valid independent records with distinct
/// business payload. `.conflictingDuplicate` must also be valid under every non-ID invariant and
/// must differ from `.original` in at least one persisted business value while reusing the supplied
/// application UUID. The duplicated UUID must be the sole intended invalid condition so a thrown
/// error cannot be satisfied by an unrelated uniqueness or validation failure.
enum IdentityContractSeedVariant: Sendable {
    case original
    case unrelatedControl
    case conflictingDuplicate
}

/// Persistence-neutral value snapshot used to prove a failed duplicate insert did not replace or
/// mutate the established entity or an unrelated same-kind control.
///
/// `payloadFingerprint` is produced by the concrete runner from stable persisted business values.
/// It must distinguish the three seed variants for the corresponding entity kind. It must not
/// contain framework object IDs, store identifiers, or other persistence-native identity.
struct IdentityContractEntitySnapshot: Equatable, Sendable {
    let id: UUID
    let payloadFingerprint: String
}

/// Target-runner control for the one identity invariant that ordinary Domain repository APIs cannot
/// directly exercise: attempting to persist two independently managed entities with the same
/// application UUID inside one repository identity/ownership scope.
///
/// A future Core Data runner should create valid records, including any required owning Herd or
/// parent relationships, without exposing managed objects or contexts to this permanent contract.
/// For herd-owned entity kinds, all seed variants must be created under the same contract Herd so
/// this probe cannot accidentally test feature-specific cross-Herd identity semantics.
/// `seedEntity` must ensure every non-ID constraint is satisfied, then surface duplicate-identity
/// persistence failure rather than translating it into an update, silently deleting/replacing the
/// original, or minting a different UUID.
@MainActor
protocol IdentityContractTestControl {
    func seedEntity(
        _ kind: IdentityContractEntityKind,
        id: UUID,
        variant: IdentityContractSeedVariant
    ) throws

    func snapshotsInIdentityScope(
        for kind: IdentityContractEntityKind,
        id: UUID
    ) throws -> [IdentityContractEntitySnapshot]

    func allEntityIDsInIdentityScope(for kind: IdentityContractEntityKind) throws -> Set<UUID>
}

/// Permanent persistence-neutral fixture for cross-cutting application identity integrity.
///
/// Each `makeTestControl` call must return a fresh access object over the same isolated backing
/// persistence and the same repository identity/ownership scope so the contract can distinguish
/// durable state from one context's in-memory state.
@MainActor
struct IdentityContractFixture {
    let makeTestControl: () -> any IdentityContractTestControl
}

/// Permanent cross-cutting application identity contract.
///
/// Ownership boundaries:
/// - Feature repository contracts own UUID preservation through ordinary create/read/update/reload
///   flows, Herd scoping, and feature-specific relationship resolution by application UUID.
/// - This contract owns duplicate application UUID rejection inside one repository identity scope
///   across every independently persisted entity and proves a failed duplicate cannot overwrite,
///   merge, delete unrelated same-kind state, or remint the logical entity.
/// - Phase 2 Core Data model-structure tests own physical UUID attribute requiredness, indexes, and
///   uniqueness-constraint declarations. Physical constraints must not be stronger than permanent
///   feature contracts such as Herd-scoped stable built-in Tag Color identities.
@MainActor
enum IdentityContract {
    static func assertDuplicateApplicationIDsFailWithoutReplacingMergingOrReminting(
        using fixture: IdentityContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for kind in IdentityContractEntityKind.allCases {
            let applicationID = UUID()
            let unrelatedControlID = UUID()

            try fixture.makeTestControl().seedEntity(
                kind,
                id: applicationID,
                variant: .original
            )
            try fixture.makeTestControl().seedEntity(
                kind,
                id: unrelatedControlID,
                variant: .unrelatedControl
            )

            let baselineControl = fixture.makeTestControl()
            let before = try baselineControl.snapshotsInIdentityScope(
                for: kind,
                id: applicationID
            )
            XCTAssertEqual(
                before.count,
                1,
                "Identity contract setup must durably create exactly one \(kind.rawValue) with the requested application UUID in the contract identity scope.",
                file: file,
                line: line
            )
            let original = try XCTUnwrap(before.first, file: file, line: line)
            XCTAssertEqual(
                original.id,
                applicationID,
                "The persisted \(kind.rawValue) must retain the UUID assigned before its first save.",
                file: file,
                line: line
            )

            let controlBefore = try baselineControl.snapshotsInIdentityScope(
                for: kind,
                id: unrelatedControlID
            )
            XCTAssertEqual(
                controlBefore.count,
                1,
                "Identity contract setup must create one unrelated \(kind.rawValue) control record.",
                file: file,
                line: line
            )
            let unrelatedControl = try XCTUnwrap(controlBefore.first, file: file, line: line)
            XCTAssertEqual(unrelatedControl.id, unrelatedControlID, file: file, line: line)
            XCTAssertNotEqual(
                unrelatedControl.payloadFingerprint,
                original.payloadFingerprint,
                "The unrelated \(kind.rawValue) control must have distinct business payload.",
                file: file,
                line: line
            )

            let idsBeforeDuplicateAttempt = try baselineControl
                .allEntityIDsInIdentityScope(for: kind)
            XCTAssertEqual(
                idsBeforeDuplicateAttempt.filter { $0 == applicationID }.count,
                1,
                "Exactly one \(kind.rawValue) may own an established application UUID inside one repository identity scope.",
                file: file,
                line: line
            )
            XCTAssertTrue(
                idsBeforeDuplicateAttempt.contains(unrelatedControlID),
                "The unrelated \(kind.rawValue) control must exist before the duplicate attempt.",
                file: file,
                line: line
            )

            XCTAssertThrowsError(
                try fixture.makeTestControl().seedEntity(
                    kind,
                    id: applicationID,
                    variant: .conflictingDuplicate
                ),
                "Persisting a second \(kind.rawValue) with an established application UUID in the same repository identity scope must fail.",
                file: file,
                line: line
            )

            let reloadControl = fixture.makeTestControl()
            let after = try reloadControl.snapshotsInIdentityScope(
                for: kind,
                id: applicationID
            )
            XCTAssertEqual(
                after,
                [original],
                "A rejected duplicate \(kind.rawValue) must not merge into, replace, or mutate the established entity after reload.",
                file: file,
                line: line
            )

            let controlAfter = try reloadControl.snapshotsInIdentityScope(
                for: kind,
                id: unrelatedControlID
            )
            XCTAssertEqual(
                controlAfter,
                [unrelatedControl],
                "A rejected duplicate \(kind.rawValue) must not mutate or remove an unrelated same-kind record.",
                file: file,
                line: line
            )

            let idsAfterDuplicateAttempt = try reloadControl
                .allEntityIDsInIdentityScope(for: kind)
            XCTAssertEqual(
                idsAfterDuplicateAttempt,
                idsBeforeDuplicateAttempt,
                "Rejecting a duplicate \(kind.rawValue) must not silently mint a replacement UUID or otherwise change the durable entity set in the contract identity scope.",
                file: file,
                line: line
            )
        }
    }
}
