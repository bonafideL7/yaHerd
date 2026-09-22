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

/// Two valid payload variants used by the target runner when probing duplicate application IDs.
///
/// The conflicting duplicate must differ from the original in at least one persisted business
/// value so the contract can detect an implementation that silently merges or overwrites the
/// established entity instead of rejecting the duplicate identity.
enum IdentityContractSeedVariant: Sendable {
    case original
    case conflictingDuplicate
}

/// Persistence-neutral value snapshot used to prove a failed duplicate insert did not replace or
/// mutate the established entity.
///
/// `payloadFingerprint` is produced by the concrete runner from stable persisted business values.
/// It must include the value that differs between `.original` and `.conflictingDuplicate` for the
/// corresponding entity kind. It must not contain framework object IDs, store identifiers, or other
/// persistence-native identity.
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
/// For herd-owned entity kinds, both seed variants must be created under the same contract Herd so
/// this probe cannot accidentally test feature-specific cross-Herd identity semantics.
/// `seedEntity` must surface duplicate-identity persistence failure rather than translating it into
/// an update, silently deleting/replacing the original, or minting a different UUID.
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
///   merge, or remint the logical entity.
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

            try fixture.makeTestControl().seedEntity(
                kind,
                id: applicationID,
                variant: .original
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

            let idsBeforeDuplicateAttempt = try baselineControl
                .allEntityIDsInIdentityScope(for: kind)
            XCTAssertEqual(
                idsBeforeDuplicateAttempt.filter { $0 == applicationID }.count,
                1,
                "Exactly one \(kind.rawValue) may own an established application UUID inside one repository identity scope.",
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
