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

    var isHerdOwned: Bool {
        self != .herd
    }
}

/// Synthetic ownership scopes used only by the future Core Data identity-contract runner.
///
/// Fresh controls for one fixture must resolve `.primaryHerd` and `.secondaryHerd` to the same
/// two persisted Herd application UUIDs. `.unscoped` is valid only for `Herd` itself.
enum IdentityContractOwningHerdScope: Equatable, Sendable {
    case unscoped
    case primaryHerd
    case secondaryHerd
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

/// Persistence-neutral value snapshot used to prove a failed duplicate insert did not replace,
/// re-home, or mutate the established entity.
///
/// `payloadFingerprint` is produced by the concrete runner from stable persisted business values.
/// It must include the value that differs between `.original` and `.conflictingDuplicate` for the
/// corresponding entity kind. It must not contain framework object IDs, store identifiers, or other
/// persistence-native identity.
struct IdentityContractEntitySnapshot: Equatable, Sendable {
    let id: UUID
    let owningHerdScope: IdentityContractOwningHerdScope
    let payloadFingerprint: String
}

/// Target-runner control for the one identity invariant that ordinary Domain repository APIs cannot
/// directly exercise: attempting to persist two independently managed entities with the same
/// application UUID.
///
/// A future Core Data runner should create valid records, including any required parent
/// relationships, without exposing managed objects or contexts to this permanent contract.
/// `seedEntity` must surface duplicate-identity persistence failure rather than translating it into
/// an update, silently deleting/replacing the original, or minting a different UUID.
///
/// For herd-owned entity kinds, the runner must persist the requested ownership relationship to the
/// fixture Herd represented by `owningHerdScope`. The same application UUID must remain invalid even
/// when the conflicting record is assigned to the other Herd.
@MainActor
protocol IdentityContractTestControl {
    func seedEntity(
        _ kind: IdentityContractEntityKind,
        id: UUID,
        variant: IdentityContractSeedVariant,
        owningHerdScope: IdentityContractOwningHerdScope
    ) throws

    func snapshots(
        for kind: IdentityContractEntityKind,
        id: UUID
    ) throws -> [IdentityContractEntitySnapshot]

    func allEntityIDs(for kind: IdentityContractEntityKind) throws -> Set<UUID>
}

/// Permanent persistence-neutral fixture for cross-cutting application identity integrity.
///
/// Each `makeTestControl` call must return a fresh access object over the same isolated backing
/// persistence so the contract can distinguish durable state from one context's in-memory state.
@MainActor
struct IdentityContractFixture {
    let makeTestControl: () -> any IdentityContractTestControl
}

/// Permanent cross-cutting application identity contract.
///
/// Ownership boundaries:
/// - Feature repository contracts own UUID preservation through ordinary create/read/update/reload
///   flows and feature-specific relationship resolution by application UUID.
/// - This contract owns duplicate application UUID rejection across every independently persisted
///   entity, including duplicates placed under different Herd roots, and proves a failed duplicate
///   cannot overwrite, merge, re-home, or remint the logical entity.
/// - Phase 2 Core Data model-structure tests own physical UUID attribute requiredness, indexes, and
///   uniqueness-constraint declarations. This contract protects observable persistence behavior.
@MainActor
enum IdentityContract {
    static func assertDuplicateApplicationIDsFailWithoutReplacingMergingOrReminting(
        using fixture: IdentityContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for kind in IdentityContractEntityKind.allCases {
            let applicationID = UUID()
            let originalScope = owningScope(for: kind)

            try fixture.makeTestControl().seedEntity(
                kind,
                id: applicationID,
                variant: .original,
                owningHerdScope: originalScope
            )

            let baselineControl = fixture.makeTestControl()
            let before = try baselineControl.snapshots(for: kind, id: applicationID)
            XCTAssertEqual(
                before.count,
                1,
                "Identity contract setup must durably create exactly one \(kind.rawValue) with the requested application UUID.",
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
            XCTAssertEqual(
                original.owningHerdScope,
                originalScope,
                "Identity contract setup must persist \(kind.rawValue) in the requested owning Herd scope.",
                file: file,
                line: line
            )

            let idsBeforeDuplicateAttempt = try baselineControl.allEntityIDs(for: kind)
            XCTAssertEqual(
                idsBeforeDuplicateAttempt.filter { $0 == applicationID }.count,
                1,
                "Exactly one \(kind.rawValue) may own an established application UUID.",
                file: file,
                line: line
            )

            XCTAssertThrowsError(
                try fixture.makeTestControl().seedEntity(
                    kind,
                    id: applicationID,
                    variant: .conflictingDuplicate,
                    owningHerdScope: originalScope
                ),
                "Persisting a second \(kind.rawValue) with an established application UUID must fail.",
                file: file,
                line: line
            )

            try assertOriginalRemainsUnchanged(
                kind: kind,
                applicationID: applicationID,
                original: original,
                idsBeforeDuplicateAttempt: idsBeforeDuplicateAttempt,
                fixture: fixture,
                failureDescription: "same-Herd duplicate rejection",
                file: file,
                line: line
            )

            guard kind.isHerdOwned else {
                continue
            }

            XCTAssertThrowsError(
                try fixture.makeTestControl().seedEntity(
                    kind,
                    id: applicationID,
                    variant: .conflictingDuplicate,
                    owningHerdScope: .secondaryHerd
                ),
                "Persisting duplicate \(kind.rawValue) identity in a different Herd must fail; application UUIDs are not Herd-namespaced.",
                file: file,
                line: line
            )

            try assertOriginalRemainsUnchanged(
                kind: kind,
                applicationID: applicationID,
                original: original,
                idsBeforeDuplicateAttempt: idsBeforeDuplicateAttempt,
                fixture: fixture,
                failureDescription: "cross-Herd duplicate rejection",
                file: file,
                line: line
            )
        }
    }

    private static func owningScope(
        for kind: IdentityContractEntityKind
    ) -> IdentityContractOwningHerdScope {
        kind.isHerdOwned ? .primaryHerd : .unscoped
    }

    private static func assertOriginalRemainsUnchanged(
        kind: IdentityContractEntityKind,
        applicationID: UUID,
        original: IdentityContractEntitySnapshot,
        idsBeforeDuplicateAttempt: Set<UUID>,
        fixture: IdentityContractFixture,
        failureDescription: String,
        file: StaticString,
        line: UInt
    ) throws {
        let reloadControl = fixture.makeTestControl()
        let after = try reloadControl.snapshots(for: kind, id: applicationID)
        XCTAssertEqual(
            after,
            [original],
            "A rejected \(kind.rawValue) \(failureDescription) must not merge into, replace, re-home, or mutate the established entity after reload.",
            file: file,
            line: line
        )

        let idsAfterDuplicateAttempt = try reloadControl.allEntityIDs(for: kind)
        XCTAssertEqual(
            idsAfterDuplicateAttempt,
            idsBeforeDuplicateAttempt,
            "A rejected \(kind.rawValue) \(failureDescription) must not silently mint a replacement UUID or otherwise change the durable entity set.",
            file: file,
            line: line
        )
    }
}
