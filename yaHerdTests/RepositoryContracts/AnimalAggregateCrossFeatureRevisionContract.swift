import Foundation
import XCTest
@testable import yaHerd

/// Every non-aggregate public write boundary that can mutate state owned by an open Animal editor.
///
/// The final Core Data implementation must rotate `AnimalAggregateRevision` for these writes just
/// as it does for `AnimalAggregateTransactionWriting.updateAnimal`. Otherwise an editor loaded
/// before the cross-feature write could still submit its old revision and overwrite newer state.
enum AnimalAggregateCrossFeatureRevisionOperation: String, CaseIterable, Sendable {
    case legacyAnimalUpdate
    case animalDeleteParentRelationshipNullification
    case directPastureMove
    case directTagAdd
    case directTagUpdate
    case directTagPromote
    case directTagRetire
    case tagColorNormalizedNameCollisionUpsert
    case fieldCheckAddTrackedAnimal
    case workingStartSession
    case workingCollectAnimals
    case workingReplacePrimaryTag
    case workingDeleteSession
    case workingCompleteSession
    case legacyPastureDelete
    case pastureDeletionTransaction

    var requiresMultipleAffectedAnimals: Bool {
        switch self {
        case .animalDeleteParentRelationshipNullification,
             .directPastureMove,
             .tagColorNormalizedNameCollisionUpsert,
             .workingStartSession,
             .workingCollectAnimals,
             .workingDeleteSession,
             .workingCompleteSession,
             .legacyPastureDelete,
             .pastureDeletionTransaction:
            return true

        case .legacyAnimalUpdate,
             .directTagAdd,
             .directTagUpdate,
             .directTagPromote,
             .directTagRetire,
             .fieldCheckAddTrackedAnimal,
             .workingReplacePrimaryTag:
            return false
        }
    }

    var requiresInactivePastureDeletionSurvivor: Bool {
        switch self {
        case .legacyPastureDelete, .pastureDeletionTransaction:
            return true
        default:
            return false
        }
    }
}

/// Target-runner control for one concrete cross-feature revision probe.
///
/// Fixture setup must prepare every Animal whose editor-owned state will be changed by the public
/// write path represented by `operation`. `affectedAnimalIDs` must be the complete changed set for
/// that one call. `performMutation()` must execute that public repository/transaction method, not a
/// test-only direct managed-object mutation.
///
/// For `.tagColorNormalizedNameCollisionUpsert`, `performMutation()` must execute
/// `TagColorRepository.upsert` with a normalized-name collision that remaps an existing current
/// AnimalTag color UUID to the canonical TagColor UUID; the representative batch must include both
/// an active-tag remap and a retired-tag remap because both belong to editor-owned aggregate state.
/// Changing only the visible color definition without remapping AnimalTag state does not satisfy that
/// case.
///
/// For `.animalDeleteParentRelationshipNullification`, `removedAnimalIDs` must identify the sire
/// and dam records deleted by one real `AnimalDeleting.delete(ids:)` call. The surviving affected
/// Animals must collectively exercise both sire and dam nullification. Deleted source parents are
/// fixture support, not affected editor aggregates, so they disappear from the post-write population.
///
/// For `.legacyPastureDelete`, `performMutation()` must execute the real
/// `PastureDeleting.delete(ids:)` boundary after fixture setup has already removed every active-in-herd
/// resident from the target Pasture(s), matching `DeletePasturesUseCase` immediately before its
/// delete call. Every affected Animal for this case must be a sold, dead, or archived survivor that
/// still references a target Pasture before deletion; `pastureDeletionInactiveSurvivorAnimalID`
/// identifies one representative member of that complete affected set.
///
/// For `.pastureDeletionTransaction`, `pastureDeletionInactiveSurvivorAnimalID` must likewise
/// identify one representative sold, dead, or archived Animal that still references a target Pasture
/// before the delete. It must be included in `affectedAnimalIDs` even though it is outside the
/// active resident move set. The same call must also affect at least one active, non-archived resident.
/// This freezes revision invalidation for both the authored resident move and relationship
/// nullification applied to inactive survivors.
///
/// The mutation must materially change editor-owned Animal attributes or tag state for every ID in
/// `affectedAnimalIDs` while leaving `unrelatedAnimalID` outside the mutation's affected set. Batch
/// operations whose single public call can fan out across Animals must supply at least two affected
/// IDs so the contract proves revision rotation for every changed member, not just one representative.
/// The isolated probe store must contain exactly those affected Animals, the one unrelated control,
/// and any explicitly declared `removedAnimalIDs` before mutation. After mutation only the affected
/// Animals and unrelated control may remain; this makes both the changed and deleted sets externally
/// observable through the real Animal repository.
/// The probe owns only revision invalidation; the operation's detailed feature semantics remain with
/// its existing permanent contract.
@MainActor
protocol AnimalAggregateCrossFeatureRevisionContractTestControl {
    var operation: AnimalAggregateCrossFeatureRevisionOperation { get }
    var affectedAnimalIDs: [UUID] { get }
    var removedAnimalIDs: [UUID] { get }
    var pastureDeletionInactiveSurvivorAnimalID: UUID? { get }
    var unrelatedAnimalID: UUID { get }

    func makeAggregateReader() -> any AnimalAggregateEditReading
    func makeAnimalRepository() -> any AnimalRepository
    func performMutation() throws
}

@MainActor
extension AnimalAggregateCrossFeatureRevisionContractTestControl {
    var removedAnimalIDs: [UUID] { [] }
    var pastureDeletionInactiveSurvivorAnimalID: UUID? { nil }
}

@MainActor
protocol AnimalParentTagDependentProjectionContractProbe {
    var makeAggregateReader: () -> any AnimalAggregateEditReading { get }
    var makeAnimalRepository: () -> any AnimalRepository { get }
    var makeAnimalListQueryReader: () -> any AnimalListQueryReading { get }
    var makeDashboardQueryReader: () -> any DashboardQueryReading { get }
    var damID: UUID { get }
    var offspringID: UUID { get }
}

@MainActor
struct AnimalLegacyUpdateTagDependentProjectionContractProbe: AnimalParentTagDependentProjectionContractProbe {
    let updater: any AnimalUpdating
    let makeAggregateReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let damID: UUID
    let offspringID: UUID
    let updateInput: AnimalInput
}

@MainActor
struct AnimalDirectTagDependentProjectionContractProbe: AnimalParentTagDependentProjectionContractProbe {
    let makeAggregateReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let damID: UUID
    let offspringID: UUID
    let addedPrimaryTagInput: AnimalTagInput
    let updatedPrimaryTagInput: AnimalTagInput
}

@MainActor
struct AnimalWorkingTagDependentProjectionContractProbe: AnimalParentTagDependentProjectionContractProbe {
    let makeAggregateReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let makeWorkingTagReplacer: () -> any WorkingPrimaryTagReplacing
    let damID: UUID
    let offspringID: UUID
    let sessionID: UUID
    let queueItemID: UUID
    let replacementInput: WorkingTagReplacementInput
}

@MainActor
struct AnimalTagColorRemapDependentProjectionContractProbe: AnimalParentTagDependentProjectionContractProbe {
    let makeAggregateReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let makeTagColorRepository: () -> any TagColorRepository
    let collisionInput: TagColorSnapshot
    let damID: UUID
    let offspringID: UUID
    let incomingColorID: UUID
    let canonicalColorID: UUID
}

@MainActor
struct AnimalParentDeletionProjectionContractProbe {
    let deleter: any AnimalDeleting
    let makeAggregateReader: () -> any AnimalAggregateEditReading
    let makeAnimalRepository: () -> any AnimalRepository
    let makeAnimalListQueryReader: () -> any AnimalListQueryReading
    let makeDashboardQueryReader: () -> any DashboardQueryReading
    let sireID: UUID
    let damID: UUID
    let offspringID: UUID
}

@MainActor
struct AnimalAggregateCrossFeatureRevisionContractFixture {
    let makeTestControl: (
        _ operation: AnimalAggregateCrossFeatureRevisionOperation
    ) throws -> any AnimalAggregateCrossFeatureRevisionContractTestControl
    let makeParentDeletionProjectionProbe: () throws -> AnimalParentDeletionProjectionContractProbe
    let makeLegacyUpdateTagDependentProjectionProbe: () throws -> AnimalLegacyUpdateTagDependentProjectionContractProbe
    let makeDirectTagDependentProjectionProbe: () throws -> AnimalDirectTagDependentProjectionContractProbe
    let makeWorkingTagDependentProjectionProbe: () throws -> AnimalWorkingTagDependentProjectionContractProbe
    let makeTagColorRemapDependentProjectionProbe: () throws -> AnimalTagColorRemapDependentProjectionContractProbe
}

/// Permanent persistence-neutral contract ensuring optimistic editor concurrency survives writes
/// originating outside the aggregate editor port.
private struct AnimalAggregateEditorOwnedState: Equatable {
    let name: String
    let sex: Sex
    let birthDate: Date
    let status: AnimalStatus
    let pastureID: UUID?
    let sireID: UUID?
    let damID: UUID?
    let distinguishingFeatures: [DistinguishingFeature]
    let saleDate: Date?
    let salePrice: Double?
    let reasonSold: String?
    let deathDate: Date?
    let causeOfDeath: String?
    let statusReferenceID: UUID?
    let activeTags: Set<AnimalTagSnapshot>
    let inactiveTags: Set<AnimalTagSnapshot>

    init(_ detail: AnimalDetailSnapshot) {
        name = detail.name
        sex = detail.sex
        birthDate = detail.birthDate
        status = detail.status
        pastureID = detail.pastureID
        sireID = detail.sireID
        damID = detail.damID
        distinguishingFeatures = detail.distinguishingFeatures
        saleDate = detail.saleDate
        salePrice = detail.salePrice
        reasonSold = detail.reasonSold
        deathDate = detail.deathDate
        causeOfDeath = detail.causeOfDeath
        statusReferenceID = detail.statusReferenceID
        activeTags = Set(detail.activeTags)
        inactiveTags = Set(detail.inactiveTags)
    }
}

private struct AnimalAggregateEditorOwnedStateExcludingPasture: Equatable {
    let name: String
    let sex: Sex
    let birthDate: Date
    let status: AnimalStatus
    let sireID: UUID?
    let damID: UUID?
    let distinguishingFeatures: [DistinguishingFeature]
    let saleDate: Date?
    let salePrice: Double?
    let reasonSold: String?
    let deathDate: Date?
    let causeOfDeath: String?
    let statusReferenceID: UUID?
    let activeTags: Set<AnimalTagSnapshot>
    let inactiveTags: Set<AnimalTagSnapshot>

    init(_ detail: AnimalDetailSnapshot) {
        name = detail.name
        sex = detail.sex
        birthDate = detail.birthDate
        status = detail.status
        sireID = detail.sireID
        damID = detail.damID
        distinguishingFeatures = detail.distinguishingFeatures
        saleDate = detail.saleDate
        salePrice = detail.salePrice
        reasonSold = detail.reasonSold
        deathDate = detail.deathDate
        causeOfDeath = detail.causeOfDeath
        statusReferenceID = detail.statusReferenceID
        activeTags = Set(detail.activeTags)
        inactiveTags = Set(detail.inactiveTags)
    }
}

private struct AnimalAggregateEditorOwnedStateExcludingParents: Equatable {
    let name: String
    let sex: Sex
    let birthDate: Date
    let status: AnimalStatus
    let pastureID: UUID?
    let distinguishingFeatures: [DistinguishingFeature]
    let saleDate: Date?
    let salePrice: Double?
    let reasonSold: String?
    let deathDate: Date?
    let causeOfDeath: String?
    let statusReferenceID: UUID?
    let activeTags: Set<AnimalTagSnapshot>
    let inactiveTags: Set<AnimalTagSnapshot>

    init(_ detail: AnimalDetailSnapshot) {
        name = detail.name
        sex = detail.sex
        birthDate = detail.birthDate
        status = detail.status
        pastureID = detail.pastureID
        distinguishingFeatures = detail.distinguishingFeatures
        saleDate = detail.saleDate
        salePrice = detail.salePrice
        reasonSold = detail.reasonSold
        deathDate = detail.deathDate
        causeOfDeath = detail.causeOfDeath
        statusReferenceID = detail.statusReferenceID
        activeTags = Set(detail.activeTags)
        inactiveTags = Set(detail.inactiveTags)
    }
}

private struct ParentDeletionAnimalSummaryState: Equatable {
    let id: UUID
    let name: String
    let displayTagNumber: String
    let displayTagColorID: UUID?
    let sex: Sex
    let animalType: AnimalType
    let firstDistinguishingFeature: String?
    let birthDate: Date
    let status: AnimalStatus
    let isArchived: Bool
    let pastureID: UUID?
    let pastureName: String?
    let location: AnimalLocation
    let lastPregnancyCheckDate: Date?
    let lastPregnancyStatus: PregnancyResult?
    let expectedCalvingDate: Date?
    let lastTreatmentDate: Date?

    init(_ summary: AnimalSummary) {
        id = summary.id
        name = summary.name
        displayTagNumber = summary.displayTagNumber
        displayTagColorID = summary.displayTagColorID
        sex = summary.sex
        animalType = summary.animalType
        firstDistinguishingFeature = summary.firstDistinguishingFeature
        birthDate = summary.birthDate
        status = summary.status
        isArchived = summary.isArchived
        pastureID = summary.pastureID
        pastureName = summary.pastureName
        location = summary.location
        lastPregnancyCheckDate = summary.lastPregnancyCheckDate
        lastPregnancyStatus = summary.lastPregnancyStatus
        expectedCalvingDate = summary.expectedCalvingDate
        lastTreatmentDate = summary.lastTreatmentDate
    }
}

private enum ParentDeletionTimelineKind: Hashable {
    case birth
    case health
    case pregnancy
    case movement
    case status
    case tag
}

private struct ParentDeletionTimelineSignature: Hashable {
    let kind: ParentDeletionTimelineKind
    let date: Date
    let title: String
    let details: String?
}

@MainActor
enum AnimalAggregateCrossFeatureRevisionContract {
    static func assertEveryCrossFeatureEditorStateMutationRotatesRevision(
        using fixture: AnimalAggregateCrossFeatureRevisionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for operation in AnimalAggregateCrossFeatureRevisionOperation.allCases {
            let control = try fixture.makeTestControl(operation)
            XCTAssertEqual(control.operation, operation, file: file, line: line)

            let affectedIDs = control.affectedAnimalIDs
            XCTAssertFalse(
                affectedIDs.isEmpty,
                "Cross-feature revision fixture for \(operation.rawValue) must identify every affected Animal.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                Set(affectedIDs).count,
                affectedIDs.count,
                "Cross-feature revision fixture for \(operation.rawValue) must not repeat affected Animal IDs.",
                file: file,
                line: line
            )
            if operation.requiresMultipleAffectedAnimals {
                XCTAssertGreaterThanOrEqual(
                    affectedIDs.count,
                    2,
                    "The \(operation.rawValue) probe must exercise one public call that changes editor-owned state for at least two Animals.",
                    file: file,
                    line: line
                )
            }
            let removedIDs = control.removedAnimalIDs
            XCTAssertEqual(
                Set(removedIDs).count,
                removedIDs.count,
                "Cross-feature revision fixture for \(operation.rawValue) must not repeat removed Animal IDs.",
                file: file,
                line: line
            )
            XCTAssertTrue(
                Set(affectedIDs).isDisjoint(with: removedIDs),
                "Removed source Animals cannot also be surviving affected editor aggregates.",
                file: file,
                line: line
            )
            XCTAssertFalse(
                Set(affectedIDs + removedIDs).contains(control.unrelatedAnimalID),
                "The unrelated revision control must remain outside the complete affected/removed Animal sets.",
                file: file,
                line: line
            )
            if operation == .animalDeleteParentRelationshipNullification {
                XCTAssertGreaterThanOrEqual(
                    removedIDs.count,
                    2,
                    "The parent-deletion probe must delete representative sire and dam source Animals in one public call.",
                    file: file,
                    line: line
                )
            } else {
                XCTAssertTrue(
                    removedIDs.isEmpty,
                    "Only the parent-deletion revision probe may remove Animal rows.",
                    file: file,
                    line: line
                )
            }

            let pastureDeletionInactiveSurvivorID = control.pastureDeletionInactiveSurvivorAnimalID
            if operation.requiresInactivePastureDeletionSurvivor {
                let survivorID = try XCTUnwrap(
                    pastureDeletionInactiveSurvivorID,
                    "Each Pasture-deletion revision probe must identify an inactive/archived Animal whose Pasture relationship is nullified by the delete boundary.",
                    file: file,
                    line: line
                )
                XCTAssertTrue(
                    affectedIDs.contains(survivorID),
                    "The inactive Pasture-deletion survivor must be part of the complete affected Animal set.",
                    file: file,
                    line: line
                )
            } else {
                XCTAssertNil(
                    pastureDeletionInactiveSurvivorID,
                    "Only Pasture-deletion revision probes may declare an inactive Pasture survivor.",
                    file: file,
                    line: line
                )
            }

            let expectedProbeAnimalIDsBefore = Set(
                affectedIDs + removedIDs + [control.unrelatedAnimalID]
            )
            let expectedProbeAnimalIDsAfter = Set(
                affectedIDs + [control.unrelatedAnimalID]
            )
            XCTAssertEqual(
                Set(try control.makeAnimalRepository().fetchAnimals().map(\.id)),
                expectedProbeAnimalIDsBefore,
                "The isolated \(operation.rawValue) probe store must contain exactly the complete affected set, declared removed sources, and one unrelated control before mutation.",
                file: file,
                line: line
            )

            var beforeByID: [UUID: AnimalAggregateEditSnapshot] = [:]
            for animalID in affectedIDs {
                let before = try XCTUnwrap(
                    control.makeAggregateReader().fetchAnimalAggregateForEditing(id: animalID),
                    "Cross-feature revision fixture must prepare every affected Animal.",
                    file: file,
                    line: line
                )
                XCTAssertEqual(before.animal.id, animalID, file: file, line: line)
                beforeByID[animalID] = before
            }

            let unrelatedBefore = try XCTUnwrap(
                control.makeAggregateReader().fetchAnimalAggregateForEditing(id: control.unrelatedAnimalID),
                "Cross-feature revision fixture must prepare an unrelated control Animal.",
                file: file,
                line: line
            )

            if operation.requiresInactivePastureDeletionSurvivor {
                let survivorID = try XCTUnwrap(pastureDeletionInactiveSurvivorID, file: file, line: line)
                let survivorBefore = try XCTUnwrap(beforeByID[survivorID], file: file, line: line)
                XCTAssertNotNil(
                    survivorBefore.animal.pastureID,
                    "The inactive Pasture-deletion survivor must reference a target Pasture before deletion.",
                    file: file,
                    line: line
                )
                XCTAssertTrue(
                    survivorBefore.animal.status != .active || survivorBefore.animal.isArchived,
                    "The Pasture-deletion nullification case must use an Animal excluded from the active resident-move set.",
                    file: file,
                    line: line
                )

                if operation == .legacyPastureDelete {
                    let allAffectedAreInactiveSurvivors = affectedIDs.allSatisfy { animalID in
                        guard let before = beforeByID[animalID] else { return false }
                        return before.animal.pastureID != nil
                            && (before.animal.status != .active || before.animal.isArchived)
                    }
                    XCTAssertTrue(
                        allAffectedAreInactiveSurvivors,
                        "The legacy Pasture delete probe must model the DeletePasturesUseCase delete step after active residents have already moved, leaving only inactive/archived relationship-nullification survivors in its affected set.",
                        file: file,
                        line: line
                    )
                } else {
                    let hasActiveResident = affectedIDs.contains { animalID in
                        guard animalID != survivorID, let before = beforeByID[animalID] else { return false }
                        return before.animal.status == .active
                            && !before.animal.isArchived
                            && before.animal.pastureID != nil
                    }
                    XCTAssertTrue(
                        hasActiveResident,
                        "The target Pasture-deletion transaction probe must retain coverage for an active resident changed by the authored atomic deletion workflow.",
                        file: file,
                        line: line
                    )
                }
            }

            try control.performMutation()

            var didRemapActiveTagColor = false
            var didRemapRetiredTagColor = false
            var didClearSireRelationship = false
            var didClearDamRelationship = false

            for animalID in affectedIDs {
                let before = try XCTUnwrap(beforeByID[animalID], file: file, line: line)
                let after = try XCTUnwrap(
                    control.makeAggregateReader().fetchAnimalAggregateForEditing(id: animalID),
                    "Every affected Animal must remain readable after \(operation.rawValue).",
                    file: file,
                    line: line
                )
                XCTAssertEqual(
                    after.animal.id,
                    before.animal.id,
                    "Cross-feature mutation must preserve application Animal identity for every affected member.",
                    file: file,
                    line: line
                )
                XCTAssertNotEqual(
                    AnimalAggregateEditorOwnedState(after.animal),
                    AnimalAggregateEditorOwnedState(before.animal),
                    "The \(operation.rawValue) fixture must materially change editor-owned Animal attributes or tag state for every listed affected Animal.",
                    file: file,
                    line: line
                )
                XCTAssertNotEqual(
                    after.revision,
                    before.revision,
                    "A \(operation.rawValue) write must rotate AnimalAggregateRevision for every affected Animal whose editor-owned state changed.",
                    file: file,
                    line: line
                )

                let isPastureDeletionNullificationSurvivor =
                    operation == .legacyPastureDelete
                    || (
                        operation == .pastureDeletionTransaction
                        && animalID == pastureDeletionInactiveSurvivorID
                    )
                if isPastureDeletionNullificationSurvivor {
                    XCTAssertNil(
                        after.animal.pastureID,
                        "Deleting the referenced Pasture must nullify the inactive survivor's editor-owned Pasture relationship.",
                        file: file,
                        line: line
                    )
                    XCTAssertEqual(
                        AnimalAggregateEditorOwnedStateExcludingPasture(after.animal),
                        AnimalAggregateEditorOwnedStateExcludingPasture(before.animal),
                        "Pasture deletion must not change any other editor-owned state on the inactive survivor.",
                        file: file,
                        line: line
                    )
                    XCTAssertEqual(
                        after.animal.isArchived,
                        before.animal.isArchived,
                        "Pasture relationship nullification must preserve the survivor's archive state.",
                        file: file,
                        line: line
                    )
                }

                if operation == .tagColorNormalizedNameCollisionUpsert {
                    didRemapActiveTagColor = didRemapActiveTagColor
                        || didChangeTagColor(
                            from: before.animal.activeTags,
                            to: after.animal.activeTags
                        )
                    didRemapRetiredTagColor = didRemapRetiredTagColor
                        || didChangeTagColor(
                            from: before.animal.inactiveTags,
                            to: after.animal.inactiveTags
                        )
                }

                if operation == .animalDeleteParentRelationshipNullification {
                    XCTAssertEqual(
                        AnimalAggregateEditorOwnedStateExcludingParents(after.animal),
                        AnimalAggregateEditorOwnedStateExcludingParents(before.animal),
                        "Hard-deleting parent Animals must not mutate any surviving offspring editor-owned state except sire/dam relationships to the deleted parents.",
                        file: file,
                        line: line
                    )

                    if let priorSireID = before.animal.sireID {
                        if removedIDs.contains(priorSireID) {
                            XCTAssertNil(
                                after.animal.sireID,
                                "A sire relationship to a deleted parent must nullify.",
                                file: file,
                                line: line
                            )
                            didClearSireRelationship = true
                        } else {
                            XCTAssertEqual(
                                after.animal.sireID,
                                priorSireID,
                                "Deleting other parent Animals must not clear a surviving sire relationship.",
                                file: file,
                                line: line
                            )
                        }
                    } else {
                        XCTAssertNil(after.animal.sireID, file: file, line: line)
                    }

                    if let priorDamID = before.animal.damID {
                        if removedIDs.contains(priorDamID) {
                            XCTAssertNil(
                                after.animal.damID,
                                "A dam relationship to a deleted parent must nullify.",
                                file: file,
                                line: line
                            )
                            didClearDamRelationship = true
                        } else {
                            XCTAssertEqual(
                                after.animal.damID,
                                priorDamID,
                                "Deleting other parent Animals must not clear a surviving dam relationship.",
                                file: file,
                                line: line
                            )
                        }
                    } else {
                        XCTAssertNil(after.animal.damID, file: file, line: line)
                    }
                }
            }

            if operation == .tagColorNormalizedNameCollisionUpsert {
                XCTAssertTrue(
                    didRemapActiveTagColor,
                    "The Tag Color collision probe must remap at least one active AnimalTag color UUID and rotate that Animal's aggregate revision.",
                    file: file,
                    line: line
                )
                XCTAssertTrue(
                    didRemapRetiredTagColor,
                    "The Tag Color collision probe must remap at least one retired AnimalTag color UUID and rotate that Animal's aggregate revision.",
                    file: file,
                    line: line
                )
            }

            if operation == .animalDeleteParentRelationshipNullification {
                XCTAssertTrue(
                    didClearSireRelationship,
                    "Hard-deleting parent Animals must exercise and invalidate at least one surviving sire relationship.",
                    file: file,
                    line: line
                )
                XCTAssertTrue(
                    didClearDamRelationship,
                    "Hard-deleting parent Animals must exercise and invalidate at least one surviving dam relationship.",
                    file: file,
                    line: line
                )
            }

            let unrelatedAfter = try XCTUnwrap(
                control.makeAggregateReader().fetchAnimalAggregateForEditing(id: control.unrelatedAnimalID),
                "The unrelated control Animal must remain readable after \(operation.rawValue).",
                file: file,
                line: line
            )
            XCTAssertEqual(
                AnimalAggregateEditorOwnedState(unrelatedAfter.animal),
                AnimalAggregateEditorOwnedState(unrelatedBefore.animal),
                "The \(operation.rawValue) probe must not mutate editor-owned state for the unrelated control Animal.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                unrelatedAfter.revision,
                unrelatedBefore.revision,
                "A \(operation.rawValue) write must not rotate AnimalAggregateRevision for an unrelated Animal whose editor-owned state did not change.",
                file: file,
                line: line
            )
            XCTAssertEqual(
                Set(try control.makeAnimalRepository().fetchAnimals().map(\.id)),
                expectedProbeAnimalIDsAfter,
                "The \(operation.rawValue) write must leave exactly the surviving affected Animals and unrelated control after removing only declared source Animals.",
                file: file,
                line: line
            )
        }
    }

    static func assertLegacyAnimalUpdateRepairsDependentTagProjections(
        using fixture: AnimalAggregateCrossFeatureRevisionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let probe = try fixture.makeLegacyUpdateTagDependentProjectionProbe()
        XCTAssertNotEqual(probe.damID, probe.offspringID, file: file, line: line)

        let beforeRepository = probe.makeAnimalRepository()
        let damBefore = try XCTUnwrap(
            beforeRepository.fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        XCTAssertEqual(damBefore.sex, .female, file: file, line: line)
        XCTAssertEqual(damBefore.status, .active, file: file, line: line)
        XCTAssertFalse(damBefore.isArchived, file: file, line: line)

        XCTAssertEqual(probe.updateInput.name, damBefore.name, file: file, line: line)
        XCTAssertEqual(probe.updateInput.sex, damBefore.sex, file: file, line: line)
        XCTAssertEqual(probe.updateInput.birthDate, damBefore.birthDate, file: file, line: line)
        XCTAssertEqual(probe.updateInput.status, damBefore.status, file: file, line: line)
        XCTAssertEqual(probe.updateInput.pastureID, damBefore.pastureID, file: file, line: line)
        XCTAssertEqual(probe.updateInput.sireID, damBefore.sireID, file: file, line: line)
        XCTAssertEqual(probe.updateInput.damID, damBefore.damID, file: file, line: line)
        XCTAssertEqual(
            probe.updateInput.distinguishingFeatures,
            damBefore.distinguishingFeatures,
            file: file,
            line: line
        )
        XCTAssertEqual(probe.updateInput.saleDate, damBefore.saleDate, file: file, line: line)
        XCTAssertEqual(probe.updateInput.salePrice, damBefore.salePrice, file: file, line: line)
        XCTAssertEqual(probe.updateInput.reasonSold, damBefore.reasonSold, file: file, line: line)
        XCTAssertEqual(probe.updateInput.deathDate, damBefore.deathDate, file: file, line: line)
        XCTAssertEqual(probe.updateInput.causeOfDeath, damBefore.causeOfDeath, file: file, line: line)
        XCTAssertEqual(
            probe.updateInput.statusReferenceID,
            damBefore.statusReferenceID,
            "The focused legacy-update fixture must isolate primary-tag propagation from every other editor-owned field.",
            file: file,
            line: line
        )

        let updatedTagNumber = probe.updateInput.tagNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(updatedTagNumber.isEmpty, file: file, line: line)
        XCTAssertNotEqual(
            updatedTagNumber,
            damBefore.displayTagNumber,
            "The focused legacy-update fixture must visibly change the current primary tag number.",
            file: file,
            line: line
        )

        let damAggregateBefore = try XCTUnwrap(
            probe.makeAggregateReader().fetchAnimalAggregateForEditing(id: probe.damID),
            file: file,
            line: line
        )
        let childBefore = try XCTUnwrap(
            probe.makeAggregateReader().fetchAnimalAggregateForEditing(id: probe.offspringID),
            file: file,
            line: line
        )
        XCTAssertEqual(childBefore.animal.damID, probe.damID, file: file, line: line)

        let childSummaryBefore = try XCTUnwrap(
            beforeRepository.fetchAnimals().first { $0.id == probe.offspringID },
            file: file,
            line: line
        )
        let childDashboardBefore = try await fetchDashboardAnimalRecord(
            id: probe.offspringID,
            reader: probe.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        let childTimelineBefore = try beforeRepository.fetchTimeline(id: probe.offspringID)
        let childPrimaryBirthBefore = try assertAndReturnPrimaryBirthProjection(
            detail: childBefore.animal,
            repository: beforeRepository,
            timeline: childTimelineBefore,
            file: file,
            line: line
        )
        let childNonPrimaryBirthBefore = multisetCounts(
            parentDeletionTimelineWithoutPrimaryBirth(
                childTimelineBefore,
                birthDate: childBefore.animal.birthDate
            )
        )

        let updated = try probe.updater.update(
            id: probe.damID,
            input: probe.updateInput
        )
        XCTAssertEqual(updated.id, probe.damID, file: file, line: line)
        XCTAssertEqual(updated.displayTagNumber, updatedTagNumber, file: file, line: line)
        XCTAssertEqual(updated.displayTagColorID, probe.updateInput.tagColorID, file: file, line: line)

        _ = try assertDamRevisionRotated(
            damID: probe.damID,
            previousRevision: damAggregateBefore.revision,
            reader: probe.makeAggregateReader(),
            operation: "legacy AnimalUpdating.update",
            file: file,
            line: line
        )

        let damAfter = try XCTUnwrap(
            probe.makeAnimalRepository().fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        XCTAssertEqual(damAfter, updated, file: file, line: line)

        try await assertParentTagDependentProjectionState(
            probe: probe,
            childRevision: childBefore.revision,
            childOwnedState: AnimalAggregateEditorOwnedState(childBefore.animal),
            childSummaryState: ParentDeletionAnimalSummaryState(childSummaryBefore),
            childDashboardState: childDashboardBefore,
            childNonPrimaryBirthTimeline: childNonPrimaryBirthBefore,
            expectedDamDetail: damAfter,
            file: file,
            line: line
        )

        let childAfter = try XCTUnwrap(
            probe.makeAggregateReader().fetchAnimalAggregateForEditing(id: probe.offspringID),
            file: file,
            line: line
        )
        let childTimelineAfter = try probe.makeAnimalRepository().fetchTimeline(id: probe.offspringID)
        let childPrimaryBirthAfter = try assertAndReturnPrimaryBirthProjection(
            detail: childAfter.animal,
            repository: probe.makeAnimalRepository(),
            timeline: childTimelineAfter,
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            childPrimaryBirthAfter.details,
            childPrimaryBirthBefore.details,
            "Changing the dam's primary tag number through legacy update must refresh the child's derived primary Birth projection.",
            file: file,
            line: line
        )
    }

    static func assertDirectTagLifecycleRepairsDependentReadProjections(
        using fixture: AnimalAggregateCrossFeatureRevisionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let probe = try fixture.makeDirectTagDependentProjectionProbe()
        XCTAssertNotEqual(probe.damID, probe.offspringID, file: file, line: line)
        XCTAssertTrue(probe.addedPrimaryTagInput.isPrimary, file: file, line: line)
        XCTAssertTrue(probe.updatedPrimaryTagInput.isPrimary, file: file, line: line)
        XCTAssertNotEqual(
            probe.addedPrimaryTagInput.number.trimmingCharacters(in: .whitespacesAndNewlines),
            probe.updatedPrimaryTagInput.number.trimmingCharacters(in: .whitespacesAndNewlines),
            "The focused direct-tag fixture must make updateTag visibly change the primary tag display.",
            file: file,
            line: line
        )

        let initialRepository = probe.makeAnimalRepository()
        let damBefore = try XCTUnwrap(
            initialRepository.fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        let childBefore = try XCTUnwrap(
            probe.makeAggregateReader().fetchAnimalAggregateForEditing(id: probe.offspringID),
            file: file,
            line: line
        )
        let damAggregateBefore = try XCTUnwrap(
            probe.makeAggregateReader().fetchAnimalAggregateForEditing(id: probe.damID),
            file: file,
            line: line
        )

        XCTAssertEqual(damBefore.sex, .female, file: file, line: line)
        XCTAssertEqual(damBefore.status, .active, file: file, line: line)
        XCTAssertFalse(damBefore.isArchived, file: file, line: line)
        XCTAssertEqual(childBefore.animal.damID, probe.damID, file: file, line: line)

        let initialPrimary = try XCTUnwrap(
            damBefore.activeTags.first { $0.isPrimary && $0.isActive },
            "The direct-tag dependency fixture must begin with an active primary dam tag.",
            file: file,
            line: line
        )
        let promotableSecondary = try XCTUnwrap(
            damBefore.activeTags.first { !$0.isPrimary && $0.isActive },
            "The direct-tag dependency fixture must begin with an active secondary dam tag for promoteTag.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            initialPrimary.normalizedNumber,
            promotableSecondary.normalizedNumber,
            "Promoting the prepared secondary tag must visibly change the dam display.",
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            probe.addedPrimaryTagInput.number.trimmingCharacters(in: .whitespacesAndNewlines),
            initialPrimary.normalizedNumber,
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            probe.updatedPrimaryTagInput.number.trimmingCharacters(in: .whitespacesAndNewlines),
            promotableSecondary.normalizedNumber,
            file: file,
            line: line
        )

        let childSummaryBefore = try XCTUnwrap(
            initialRepository.fetchAnimals().first { $0.id == probe.offspringID },
            file: file,
            line: line
        )
        let childDashboardBefore = try await fetchDashboardAnimalRecord(
            id: probe.offspringID,
            reader: probe.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        let childTimelineBefore = try initialRepository.fetchTimeline(id: probe.offspringID)
        let childNonPrimaryBirthBefore = multisetCounts(
            parentDeletionTimelineWithoutPrimaryBirth(
                childTimelineBefore,
                birthDate: childBefore.animal.birthDate
            )
        )
        let childOwnedStateBefore = AnimalAggregateEditorOwnedState(childBefore.animal)

        try await assertParentTagDependentProjectionState(
            probe: probe,
            childRevision: childBefore.revision,
            childOwnedState: childOwnedStateBefore,
            childSummaryState: ParentDeletionAnimalSummaryState(childSummaryBefore),
            childDashboardState: childDashboardBefore,
            childNonPrimaryBirthTimeline: childNonPrimaryBirthBefore,
            expectedDamDetail: damBefore,
            file: file,
            line: line
        )

        let afterAdd = try probe.makeAnimalRepository().addTag(
            animalID: probe.damID,
            input: probe.addedPrimaryTagInput
        )
        let addedTag = try XCTUnwrap(
            afterAdd.activeTags.first {
                $0.isPrimary
                    && $0.normalizedNumber
                        == probe.addedPrimaryTagInput.number.trimmingCharacters(in: .whitespacesAndNewlines)
            },
            "addTag must persist the requested new primary tag before dependent projections are checked.",
            file: file,
            line: line
        )
        var previousDamRevision = damAggregateBefore.revision
        previousDamRevision = try assertDamRevisionRotated(
            damID: probe.damID,
            previousRevision: previousDamRevision,
            reader: probe.makeAggregateReader(),
            operation: "addTag",
            file: file,
            line: line
        )
        let reloadedAfterAdd = try XCTUnwrap(
            probe.makeAnimalRepository().fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        try await assertParentTagDependentProjectionState(
            probe: probe,
            childRevision: childBefore.revision,
            childOwnedState: childOwnedStateBefore,
            childSummaryState: ParentDeletionAnimalSummaryState(childSummaryBefore),
            childDashboardState: childDashboardBefore,
            childNonPrimaryBirthTimeline: childNonPrimaryBirthBefore,
            expectedDamDetail: reloadedAfterAdd,
            file: file,
            line: line
        )

        _ = try probe.makeAnimalRepository().updateTag(
            animalID: probe.damID,
            tagID: addedTag.id,
            input: probe.updatedPrimaryTagInput
        )
        previousDamRevision = try assertDamRevisionRotated(
            damID: probe.damID,
            previousRevision: previousDamRevision,
            reader: probe.makeAggregateReader(),
            operation: "updateTag",
            file: file,
            line: line
        )
        let reloadedAfterUpdate = try XCTUnwrap(
            probe.makeAnimalRepository().fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedAfterUpdate.displayTagNumber,
            probe.updatedPrimaryTagInput.number.trimmingCharacters(in: .whitespacesAndNewlines),
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedAfterUpdate.displayTagColorID, probe.updatedPrimaryTagInput.colorID, file: file, line: line)
        try await assertParentTagDependentProjectionState(
            probe: probe,
            childRevision: childBefore.revision,
            childOwnedState: childOwnedStateBefore,
            childSummaryState: ParentDeletionAnimalSummaryState(childSummaryBefore),
            childDashboardState: childDashboardBefore,
            childNonPrimaryBirthTimeline: childNonPrimaryBirthBefore,
            expectedDamDetail: reloadedAfterUpdate,
            file: file,
            line: line
        )

        _ = try probe.makeAnimalRepository().promoteTag(
            animalID: probe.damID,
            tagID: promotableSecondary.id
        )
        previousDamRevision = try assertDamRevisionRotated(
            damID: probe.damID,
            previousRevision: previousDamRevision,
            reader: probe.makeAggregateReader(),
            operation: "promoteTag",
            file: file,
            line: line
        )
        let reloadedAfterPromote = try XCTUnwrap(
            probe.makeAnimalRepository().fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        XCTAssertEqual(reloadedAfterPromote.displayTagNumber, promotableSecondary.normalizedNumber, file: file, line: line)
        XCTAssertEqual(reloadedAfterPromote.displayTagColorID, promotableSecondary.colorID, file: file, line: line)
        try await assertParentTagDependentProjectionState(
            probe: probe,
            childRevision: childBefore.revision,
            childOwnedState: childOwnedStateBefore,
            childSummaryState: ParentDeletionAnimalSummaryState(childSummaryBefore),
            childDashboardState: childDashboardBefore,
            childNonPrimaryBirthTimeline: childNonPrimaryBirthBefore,
            expectedDamDetail: reloadedAfterPromote,
            file: file,
            line: line
        )

        _ = try probe.makeAnimalRepository().retireTag(
            animalID: probe.damID,
            tagID: promotableSecondary.id
        )
        _ = try assertDamRevisionRotated(
            damID: probe.damID,
            previousRevision: previousDamRevision,
            reader: probe.makeAggregateReader(),
            operation: "retireTag",
            file: file,
            line: line
        )
        let reloadedAfterRetire = try XCTUnwrap(
            probe.makeAnimalRepository().fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        XCTAssertFalse(
            reloadedAfterRetire.activeTags.contains { $0.id == promotableSecondary.id },
            file: file,
            line: line
        )
        XCTAssertTrue(
            reloadedAfterRetire.inactiveTags.contains { $0.id == promotableSecondary.id },
            file: file,
            line: line
        )
        XCTAssertEqual(
            reloadedAfterRetire.displayTagNumber,
            probe.updatedPrimaryTagInput.number.trimmingCharacters(in: .whitespacesAndNewlines),
            "Retiring the promoted secondary must restore the surviving updated tag as the current display.",
            file: file,
            line: line
        )
        try await assertParentTagDependentProjectionState(
            probe: probe,
            childRevision: childBefore.revision,
            childOwnedState: childOwnedStateBefore,
            childSummaryState: ParentDeletionAnimalSummaryState(childSummaryBefore),
            childDashboardState: childDashboardBefore,
            childNonPrimaryBirthTimeline: childNonPrimaryBirthBefore,
            expectedDamDetail: reloadedAfterRetire,
            file: file,
            line: line
        )
    }


    static func assertWorkingTagReplacementRepairsDependentReadProjections(
        using fixture: AnimalAggregateCrossFeatureRevisionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let probe = try fixture.makeWorkingTagDependentProjectionProbe()
        let replacementNumber = probe.replacementInput.number.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(replacementNumber.isEmpty, file: file, line: line)

        let beforeRepository = probe.makeAnimalRepository()
        let damBefore = try XCTUnwrap(
            beforeRepository.fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            damBefore.displayTagNumber,
            replacementNumber,
            "The focused Working replacement fixture must visibly change the parent's current tag number.",
            file: file,
            line: line
        )
        let damAggregateBefore = try XCTUnwrap(
            probe.makeAggregateReader().fetchAnimalAggregateForEditing(id: probe.damID),
            file: file,
            line: line
        )
        let childBefore = try XCTUnwrap(
            probe.makeAggregateReader().fetchAnimalAggregateForEditing(id: probe.offspringID),
            file: file,
            line: line
        )
        XCTAssertEqual(childBefore.animal.damID, probe.damID, file: file, line: line)

        let childSummaryBefore = try XCTUnwrap(
            beforeRepository.fetchAnimals().first { $0.id == probe.offspringID },
            file: file,
            line: line
        )
        let childDashboardBefore = try await fetchDashboardAnimalRecord(
            id: probe.offspringID,
            reader: probe.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        let childTimelineBefore = try beforeRepository.fetchTimeline(id: probe.offspringID)
        let childNonPrimaryBirthBefore = multisetCounts(
            parentDeletionTimelineWithoutPrimaryBirth(
                childTimelineBefore,
                birthDate: childBefore.animal.birthDate
            )
        )

        let replacement = try probe.makeWorkingTagReplacer().replacePrimaryTag(
            forQueueItemID: probe.queueItemID,
            inSessionID: probe.sessionID,
            input: probe.replacementInput
        )
        XCTAssertEqual(replacement.animalDisplayTagNumber, replacementNumber, file: file, line: line)
        XCTAssertEqual(replacement.animalDisplayTagColorID, probe.replacementInput.colorID, file: file, line: line)

        let damAfter = try XCTUnwrap(
            probe.makeAnimalRepository().fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        XCTAssertEqual(damAfter.displayTagNumber, replacementNumber, file: file, line: line)
        XCTAssertEqual(damAfter.displayTagColorID, probe.replacementInput.colorID, file: file, line: line)
        _ = try assertDamRevisionRotated(
            damID: probe.damID,
            previousRevision: damAggregateBefore.revision,
            reader: probe.makeAggregateReader(),
            operation: "Working replacePrimaryTag",
            file: file,
            line: line
        )

        try await assertParentTagDependentProjectionState(
            probe: probe,
            childRevision: childBefore.revision,
            childOwnedState: AnimalAggregateEditorOwnedState(childBefore.animal),
            childSummaryState: ParentDeletionAnimalSummaryState(childSummaryBefore),
            childDashboardState: childDashboardBefore,
            childNonPrimaryBirthTimeline: childNonPrimaryBirthBefore,
            expectedDamDetail: damAfter,
            file: file,
            line: line
        )
    }

    static func assertTagColorCollisionRemapRepairsDependentReadProjections(
        using fixture: AnimalAggregateCrossFeatureRevisionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let probe = try fixture.makeTagColorRemapDependentProjectionProbe()
        XCTAssertNotEqual(probe.incomingColorID, probe.canonicalColorID, file: file, line: line)
        XCTAssertEqual(
            probe.collisionInput.id,
            probe.incomingColorID,
            "The focused collision input must identify the duplicate color that will be reconciled away.",
            file: file,
            line: line
        )

        let beforeRepository = probe.makeAnimalRepository()
        let damBefore = try XCTUnwrap(
            beforeRepository.fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        XCTAssertFalse(
            damBefore.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            file: file,
            line: line
        )
        XCTAssertEqual(
            damBefore.displayTagColorID,
            probe.incomingColorID,
            "The focused Tag Color remap fixture must begin with the parent's live display tag referencing the incoming duplicate color UUID.",
            file: file,
            line: line
        )
        let damAggregateBefore = try XCTUnwrap(
            probe.makeAggregateReader().fetchAnimalAggregateForEditing(id: probe.damID),
            file: file,
            line: line
        )
        let childBefore = try XCTUnwrap(
            probe.makeAggregateReader().fetchAnimalAggregateForEditing(id: probe.offspringID),
            file: file,
            line: line
        )
        XCTAssertEqual(childBefore.animal.damID, probe.damID, file: file, line: line)

        let childSummaryBefore = try XCTUnwrap(
            beforeRepository.fetchAnimals().first { $0.id == probe.offspringID },
            file: file,
            line: line
        )
        XCTAssertEqual(childSummaryBefore.damDisplayTagColorID, probe.incomingColorID, file: file, line: line)
        let childDashboardBefore = try await fetchDashboardAnimalRecord(
            id: probe.offspringID,
            reader: probe.makeDashboardQueryReader(),
            file: file,
            line: line
        )
        XCTAssertEqual(childDashboardBefore.damDisplayTagColorID, probe.incomingColorID, file: file, line: line)
        let childTimelineBefore = try beforeRepository.fetchTimeline(id: probe.offspringID)
        let completeChildTimelineBefore = multisetCounts(
            parentDeletionTimelineSignatures(childTimelineBefore)
        )
        let childNonPrimaryBirthBefore = multisetCounts(
            parentDeletionTimelineWithoutPrimaryBirth(
                childTimelineBefore,
                birthDate: childBefore.animal.birthDate
            )
        )

        try probe.makeTagColorRepository().upsert(probe.collisionInput)

        let damAfter = try XCTUnwrap(
            probe.makeAnimalRepository().fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            damAfter.displayTagNumber,
            damBefore.displayTagNumber,
            "A Tag Color identity reconciliation must not rewrite the live tag number.",
            file: file,
            line: line
        )
        XCTAssertEqual(damAfter.displayTagColorID, probe.canonicalColorID, file: file, line: line)
        _ = try assertDamRevisionRotated(
            damID: probe.damID,
            previousRevision: damAggregateBefore.revision,
            reader: probe.makeAggregateReader(),
            operation: "Tag Color normalized-name collision upsert",
            file: file,
            line: line
        )

        try await assertParentTagDependentProjectionState(
            probe: probe,
            childRevision: childBefore.revision,
            childOwnedState: AnimalAggregateEditorOwnedState(childBefore.animal),
            childSummaryState: ParentDeletionAnimalSummaryState(childSummaryBefore),
            childDashboardState: childDashboardBefore,
            childNonPrimaryBirthTimeline: childNonPrimaryBirthBefore,
            expectedDamDetail: damAfter,
            file: file,
            line: line
        )

        XCTAssertEqual(
            multisetCounts(
                parentDeletionTimelineSignatures(
                    try probe.makeAnimalRepository().fetchTimeline(id: probe.offspringID)
                )
            ),
            completeChildTimelineBefore,
            "A color-only parent Tag Color identity remap must not rewrite the child's number-derived Birth projection or any durable child history.",
            file: file,
            line: line
        )
        let childSummaryAfter = try XCTUnwrap(
            probe.makeAnimalRepository().fetchAnimals().first { $0.id == probe.offspringID },
            file: file,
            line: line
        )
        XCTAssertEqual(childSummaryAfter.damDisplayTagNumber, childSummaryBefore.damDisplayTagNumber, file: file, line: line)
        XCTAssertEqual(childSummaryAfter.damDisplayTagColorID, probe.canonicalColorID, file: file, line: line)
    }

    static func assertParentDeletionRepairsDependentReadProjections(
        using fixture: AnimalAggregateCrossFeatureRevisionContractFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let probe = try fixture.makeParentDeletionProjectionProbe()
        XCTAssertNotEqual(probe.sireID, probe.damID, file: file, line: line)
        XCTAssertFalse(
            [probe.sireID, probe.damID].contains(probe.offspringID),
            "The surviving offspring must be distinct from both deleted parents.",
            file: file,
            line: line
        )

        let expectedBeforeIDs = Set([probe.sireID, probe.damID, probe.offspringID])
        let beforeRepository = probe.makeAnimalRepository()
        XCTAssertEqual(
            Set(try beforeRepository.fetchAnimals().map(\.id)),
            expectedBeforeIDs,
            "The focused parent-delete projection fixture must contain exactly one sire, one dam, and their surviving offspring.",
            file: file,
            line: line
        )

        let sireBefore = try XCTUnwrap(
            beforeRepository.fetchAnimalDetail(id: probe.sireID),
            file: file,
            line: line
        )
        let damBefore = try XCTUnwrap(
            beforeRepository.fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        let childBefore = try XCTUnwrap(
            probe.makeAggregateReader().fetchAnimalAggregateForEditing(id: probe.offspringID),
            file: file,
            line: line
        )
        XCTAssertEqual(childBefore.animal.sireID, probe.sireID, file: file, line: line)
        XCTAssertEqual(childBefore.animal.damID, probe.damID, file: file, line: line)
        XCTAssertEqual(childBefore.animal.sire, sireBefore.displayTagNumber, file: file, line: line)
        XCTAssertEqual(childBefore.animal.dam, damBefore.displayTagNumber, file: file, line: line)
        XCTAssertFalse(
            (childBefore.animal.sire ?? "").isEmpty,
            "The focused parent-delete fixture must begin with a visible sire display.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            (childBefore.animal.dam ?? "").isEmpty,
            "The focused parent-delete fixture must begin with a visible dam display.",
            file: file,
            line: line
        )

        let childSummaryBefore = try XCTUnwrap(
            beforeRepository.fetchAnimals().first { $0.id == probe.offspringID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            childSummaryBefore.damDisplayTagNumber,
            AnimalDisplayTagFormatter.displayTagNumber(from: damBefore.displayTagNumber),
            file: file,
            line: line
        )
        XCTAssertEqual(
            childSummaryBefore.damDisplayTagColorID,
            damBefore.displayTagColorID,
            file: file,
            line: line
        )

        let pageBefore = try await probe.makeAnimalListQueryReader().fetchAnimalSummaryPage(
            ReadPageRequest(offset: 0, limit: ReadPageRequest.maximumLimit)
        )
        XCTAssertFalse(
            pageBefore.hasMore,
            "The isolated parent-delete projection fixture must fit in one maximum-size Animal-list page.",
            file: file,
            line: line
        )
        XCTAssertEqual(Set(pageBefore.animals.map(\.id)), expectedBeforeIDs, file: file, line: line)
        XCTAssertEqual(
            try XCTUnwrap(pageBefore.animals.first { $0.id == probe.offspringID }, file: file, line: line),
            childSummaryBefore,
            file: file,
            line: line
        )

        let dashboardBefore = try await probe.makeDashboardQueryReader().fetchDashboardRecords()
        XCTAssertEqual(Set(dashboardBefore.animals.map(\.id)), expectedBeforeIDs, file: file, line: line)
        let childDashboardBefore = try XCTUnwrap(
            dashboardBefore.animals.first { $0.id == probe.offspringID },
            file: file,
            line: line
        )
        XCTAssertEqual(childDashboardBefore.damID, probe.damID, file: file, line: line)
        XCTAssertEqual(
            childDashboardBefore.damDisplayTagNumber,
            childSummaryBefore.damDisplayTagNumber,
            file: file,
            line: line
        )
        XCTAssertEqual(
            childDashboardBefore.damDisplayTagColorID,
            childSummaryBefore.damDisplayTagColorID,
            file: file,
            line: line
        )

        let timelineBefore = try beforeRepository.fetchTimeline(id: probe.offspringID)
        let primaryBirthBefore = try assertAndReturnPrimaryBirthProjection(
            detail: childBefore.animal,
            repository: beforeRepository,
            timeline: timelineBefore,
            file: file,
            line: line
        )

        try probe.deleter.delete(ids: [probe.sireID, probe.damID])

        let afterRepository = probe.makeAnimalRepository()
        XCTAssertNil(try afterRepository.fetchAnimalDetail(id: probe.sireID), file: file, line: line)
        XCTAssertNil(try afterRepository.fetchAnimalDetail(id: probe.damID), file: file, line: line)
        XCTAssertEqual(
            Set(try afterRepository.fetchAnimals().map(\.id)),
            Set([probe.offspringID]),
            "One hard-delete call must remove both parent rows while preserving the offspring.",
            file: file,
            line: line
        )
        let parentOptionsAfter = try afterRepository.fetchParentOptions(excluding: nil)
        XCTAssertFalse(parentOptionsAfter.contains { $0.id == probe.sireID }, file: file, line: line)
        XCTAssertFalse(parentOptionsAfter.contains { $0.id == probe.damID }, file: file, line: line)

        let childAfter = try XCTUnwrap(
            probe.makeAggregateReader().fetchAnimalAggregateForEditing(id: probe.offspringID),
            file: file,
            line: line
        )
        XCTAssertEqual(childAfter.animal.id, childBefore.animal.id, file: file, line: line)
        XCTAssertNotEqual(
            childAfter.revision,
            childBefore.revision,
            "Hard-deleting either referenced parent changes editor-owned child relationship state and must rotate the surviving child revision.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            AnimalAggregateEditorOwnedStateExcludingParents(childAfter.animal),
            AnimalAggregateEditorOwnedStateExcludingParents(childBefore.animal),
            "Parent hard-delete must preserve every surviving child editor-owned value except the deleted parent relationships.",
            file: file,
            line: line
        )
        XCTAssertNil(childAfter.animal.sireID, file: file, line: line)
        XCTAssertNil(childAfter.animal.damID, file: file, line: line)
        XCTAssertNil(childAfter.animal.sire, file: file, line: line)
        XCTAssertNil(childAfter.animal.dam, file: file, line: line)

        let childSummaryAfter = try XCTUnwrap(
            afterRepository.fetchAnimals().first { $0.id == probe.offspringID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            ParentDeletionAnimalSummaryState(childSummaryAfter),
            ParentDeletionAnimalSummaryState(childSummaryBefore),
            "Deleting parents must preserve every child AnimalSummary value other than derived dam display fields.",
            file: file,
            line: line
        )
        XCTAssertNil(childSummaryAfter.damDisplayTagNumber, file: file, line: line)
        XCTAssertNil(childSummaryAfter.damDisplayTagColorID, file: file, line: line)

        let pageAfter = try await probe.makeAnimalListQueryReader().fetchAnimalSummaryPage(
            ReadPageRequest(offset: 0, limit: ReadPageRequest.maximumLimit)
        )
        XCTAssertFalse(pageAfter.hasMore, file: file, line: line)
        XCTAssertEqual(Set(pageAfter.animals.map(\.id)), Set([probe.offspringID]), file: file, line: line)
        XCTAssertEqual(
            try XCTUnwrap(pageAfter.animals.first, file: file, line: line),
            childSummaryAfter,
            "The production paged Animal-list projection must clear the deleted dam display consistently.",
            file: file,
            line: line
        )

        let dashboardAfter = try await probe.makeDashboardQueryReader().fetchDashboardRecords()
        XCTAssertEqual(Set(dashboardAfter.animals.map(\.id)), Set([probe.offspringID]), file: file, line: line)
        let childDashboardAfter = try XCTUnwrap(
            dashboardAfter.animals.first,
            file: file,
            line: line
        )
        assertDashboardParentDeletionPreservesChildState(
            childDashboardAfter,
            before: childDashboardBefore,
            file: file,
            line: line
        )
        XCTAssertNil(childDashboardAfter.damID, file: file, line: line)
        XCTAssertNil(childDashboardAfter.damDisplayTagNumber, file: file, line: line)
        XCTAssertNil(childDashboardAfter.damDisplayTagColorID, file: file, line: line)

        let timelineAfter = try afterRepository.fetchTimeline(id: probe.offspringID)
        XCTAssertEqual(
            multisetCounts(
                parentDeletionTimelineWithoutPrimaryBirth(
                    timelineAfter,
                    birthDate: childAfter.animal.birthDate
                )
            ),
            multisetCounts(
                parentDeletionTimelineWithoutPrimaryBirth(
                    timelineBefore,
                    birthDate: childBefore.animal.birthDate
                )
            ),
            "Parent hard-delete must not add, remove, or rewrite surviving child history outside the derived primary Birth projection.",
            file: file,
            line: line
        )
        let primaryBirthAfter = try assertAndReturnPrimaryBirthProjection(
            detail: childAfter.animal,
            repository: afterRepository,
            timeline: timelineAfter,
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            primaryBirthAfter.details,
            primaryBirthBefore.details,
            "The surviving child primary Birth projection must drop deleted parent displays.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            (primaryBirthAfter.details ?? "").contains("Dam:"),
            "The derived Birth projection must not retain a deleted dam display.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            (primaryBirthAfter.details ?? "").contains("Sire:"),
            "The derived Birth projection must not retain a deleted sire display.",
            file: file,
            line: line
        )
    }

    private static func assertDamRevisionRotated(
        damID: UUID,
        previousRevision: AnimalAggregateRevision,
        reader: any AnimalAggregateEditReading,
        operation: String,
        file: StaticString,
        line: UInt
    ) throws -> AnimalAggregateRevision {
        let reloaded = try XCTUnwrap(
            reader.fetchAnimalAggregateForEditing(id: damID),
            file: file,
            line: line
        )
        XCTAssertNotEqual(
            reloaded.revision,
            previousRevision,
            "\(operation) changes authoritative dam tag state and must rotate the dam aggregate revision.",
            file: file,
            line: line
        )
        return reloaded.revision
    }

    private static func assertParentTagDependentProjectionState(
        probe: any AnimalParentTagDependentProjectionContractProbe,
        childRevision: AnimalAggregateRevision,
        childOwnedState: AnimalAggregateEditorOwnedState,
        childSummaryState: ParentDeletionAnimalSummaryState,
        childDashboardState: DashboardAnimalRecord,
        childNonPrimaryBirthTimeline: [ParentDeletionTimelineSignature: Int],
        expectedDamDetail: AnimalDetailSnapshot,
        file: StaticString,
        line: UInt
    ) async throws {
        let repository = probe.makeAnimalRepository()
        let damDetail = try XCTUnwrap(
            repository.fetchAnimalDetail(id: probe.damID),
            file: file,
            line: line
        )
        XCTAssertEqual(damDetail, expectedDamDetail, file: file, line: line)
        XCTAssertFalse(
            damDetail.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "The focused parent-tag projection fixture keeps a visible current dam tag at every projection checkpoint.",
            file: file,
            line: line
        )

        let damSummary = try XCTUnwrap(
            repository.fetchAnimals().first { $0.id == probe.damID },
            file: file,
            line: line
        )
        XCTAssertEqual(damSummary.displayTagNumber, damDetail.displayTagNumber, file: file, line: line)
        XCTAssertEqual(damSummary.displayTagColorID, damDetail.displayTagColorID, file: file, line: line)

        let child = try XCTUnwrap(
            probe.makeAggregateReader().fetchAnimalAggregateForEditing(id: probe.offspringID),
            file: file,
            line: line
        )
        XCTAssertEqual(
            child.revision,
            childRevision,
            "Changing a parent's tag display must not rotate a surviving child's aggregate revision when the child's editor-owned relationship identity is unchanged.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            AnimalAggregateEditorOwnedState(child.animal),
            childOwnedState,
            "Parent tag mutations must not mutate child editor-owned aggregate state.",
            file: file,
            line: line
        )
        XCTAssertEqual(child.animal.damID, probe.damID, file: file, line: line)
        XCTAssertEqual(child.animal.dam, damDetail.displayTagNumber, file: file, line: line)

        let childSummary = try XCTUnwrap(
            repository.fetchAnimals().first { $0.id == probe.offspringID },
            file: file,
            line: line
        )
        XCTAssertEqual(
            ParentDeletionAnimalSummaryState(childSummary),
            childSummaryState,
            "Parent tag mutations must preserve every child summary value outside the derived dam display fields.",
            file: file,
            line: line
        )
        XCTAssertEqual(childSummary.damDisplayTagNumber, damDetail.displayTagNumber, file: file, line: line)
        XCTAssertEqual(childSummary.damDisplayTagColorID, damDetail.displayTagColorID, file: file, line: line)

        let page = try await probe.makeAnimalListQueryReader().fetchAnimalSummaryPage(
            ReadPageRequest(offset: 0, limit: ReadPageRequest.maximumLimit)
        )
        XCTAssertFalse(
            page.hasMore,
            "The focused parent-tag dependency fixture must fit in one maximum-size Animal-list page.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(page.animals.first { $0.id == probe.damID }, file: file, line: line),
            damSummary,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try XCTUnwrap(page.animals.first { $0.id == probe.offspringID }, file: file, line: line),
            childSummary,
            file: file,
            line: line
        )

        let parentOption = try XCTUnwrap(
            repository.fetchParentOptions(excluding: nil).first { $0.id == probe.damID },
            file: file,
            line: line
        )
        XCTAssertEqual(parentOption.displayTagNumber, damDetail.displayTagNumber, file: file, line: line)
        XCTAssertEqual(parentOption.displayTagColorID, damDetail.displayTagColorID, file: file, line: line)

        let offspringSeed = try XCTUnwrap(
            repository.fetchOffspringDraftSeed(forDamID: probe.damID),
            file: file,
            line: line
        )
        XCTAssertEqual(offspringSeed.damID, probe.damID, file: file, line: line)
        XCTAssertEqual(offspringSeed.damDisplayName, parentOption.displayName, file: file, line: line)

        let dashboard = try await probe.makeDashboardQueryReader().fetchDashboardRecords()
        let damDashboard = try XCTUnwrap(
            dashboard.animals.first { $0.id == probe.damID },
            file: file,
            line: line
        )
        XCTAssertEqual(damDashboard.displayTagNumber, damDetail.displayTagNumber, file: file, line: line)
        XCTAssertEqual(damDashboard.displayTagColorID, damDetail.displayTagColorID, file: file, line: line)

        let childDashboard = try XCTUnwrap(
            dashboard.animals.first { $0.id == probe.offspringID },
            file: file,
            line: line
        )
        assertDashboardParentDeletionPreservesChildState(
            childDashboard,
            before: childDashboardState,
            file: file,
            line: line
        )
        XCTAssertEqual(childDashboard.damID, probe.damID, file: file, line: line)
        XCTAssertEqual(childDashboard.damDisplayTagNumber, damDetail.displayTagNumber, file: file, line: line)
        XCTAssertEqual(childDashboard.damDisplayTagColorID, damDetail.displayTagColorID, file: file, line: line)

        let timeline = try repository.fetchTimeline(id: probe.offspringID)
        XCTAssertEqual(
            multisetCounts(
                parentDeletionTimelineWithoutPrimaryBirth(
                    timeline,
                    birthDate: child.animal.birthDate
                )
            ),
            childNonPrimaryBirthTimeline,
            "Parent tag mutations must not add, remove, or rewrite child history outside the derived primary Birth projection.",
            file: file,
            line: line
        )
        let primaryBirth = try assertAndReturnPrimaryBirthProjection(
            detail: child.animal,
            repository: repository,
            timeline: timeline,
            file: file,
            line: line
        )
        XCTAssertTrue(
            (primaryBirth.details ?? "").contains("Dam: \(damDetail.displayTagNumber)"),
            "The child's derived primary Birth projection must reflect the dam's current tag display.",
            file: file,
            line: line
        )
    }

    private static func assertDashboardParentDeletionPreservesChildState(
        _ actual: DashboardAnimalRecord,
        before: DashboardAnimalRecord,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual.id, before.id, file: file, line: line)
        XCTAssertEqual(actual.displayTagNumber, before.displayTagNumber, file: file, line: line)
        XCTAssertEqual(actual.displayTagColorID, before.displayTagColorID, file: file, line: line)
        XCTAssertEqual(actual.sex, before.sex, file: file, line: line)
        XCTAssertEqual(actual.animalType, before.animalType, file: file, line: line)
        XCTAssertEqual(actual.status, before.status, file: file, line: line)
        XCTAssertEqual(actual.isArchived, before.isArchived, file: file, line: line)
        XCTAssertEqual(actual.pastureID, before.pastureID, file: file, line: line)
        XCTAssertEqual(actual.pastureName, before.pastureName, file: file, line: line)
        XCTAssertEqual(actual.location, before.location, file: file, line: line)
        XCTAssertEqual(actual.lastPregnancyCheckDate, before.lastPregnancyCheckDate, file: file, line: line)
        XCTAssertEqual(actual.lastPregnancyStatus, before.lastPregnancyStatus, file: file, line: line)
        XCTAssertEqual(actual.expectedCalvingDate, before.expectedCalvingDate, file: file, line: line)
        XCTAssertEqual(actual.lastTreatmentDate, before.lastTreatmentDate, file: file, line: line)
        XCTAssertEqual(actual.birthDate, before.birthDate, file: file, line: line)
        XCTAssertEqual(actual.saleDate, before.saleDate, file: file, line: line)
        XCTAssertEqual(actual.deathDate, before.deathDate, file: file, line: line)
        XCTAssertEqual(
            multisetCounts(actual.healthRecords),
            multisetCounts(before.healthRecords),
            file: file,
            line: line
        )
        XCTAssertEqual(actual.offspringCount, before.offspringCount, file: file, line: line)
    }

    private static func parentDeletionTimelineWithoutPrimaryBirth(
        _ timeline: [AnimalTimelineEvent],
        birthDate: Date
    ) -> [ParentDeletionTimelineSignature] {
        parentDeletionTimelineSignatures(timeline).filter {
            !($0.kind == .birth && $0.title == "Birth" && $0.date == birthDate)
        }
    }

    private static func assertAndReturnPrimaryBirthProjection(
        detail: AnimalDetailSnapshot,
        repository: any AnimalRepository,
        timeline: [AnimalTimelineEvent],
        file: StaticString,
        line: UInt
    ) throws -> ParentDeletionTimelineSignature {
        let primaryBirths = parentDeletionTimelineSignatures(timeline).filter {
            $0.kind == .birth && $0.title == "Birth" && $0.date == detail.birthDate
        }
        XCTAssertEqual(primaryBirths.count, 1, file: file, line: line)
        let actual = try XCTUnwrap(primaryBirths.first, file: file, line: line)

        let damDisplay = try detail.damID.flatMap { damID in
            try repository.fetchAnimalDetail(id: damID)?
                .displayTagNumber
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let sireDisplay = try detail.sireID.flatMap { sireID in
            try repository.fetchAnimalDetail(id: sireID)?
                .displayTagNumber
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var details: [String] = []
        if let damDisplay, !damDisplay.isEmpty {
            details.append("Dam: \(damDisplay)")
        }
        if let sireDisplay, !sireDisplay.isEmpty {
            details.append("Sire: \(sireDisplay)")
        }
        if let pastureName = detail.pastureName, !pastureName.isEmpty {
            details.append("Pasture: \(pastureName)")
        }
        XCTAssertEqual(
            actual.details,
            details.isEmpty ? nil : details.joined(separator: " • "),
            "The primary Birth projection must derive from the surviving child's current parent/Pasture relationships.",
            file: file,
            line: line
        )
        return actual
    }

    private static func parentDeletionTimelineSignatures(
        _ timeline: [AnimalTimelineEvent]
    ) -> [ParentDeletionTimelineSignature] {
        timeline.map { event in
            ParentDeletionTimelineSignature(
                kind: parentDeletionTimelineKind(event.type),
                date: event.date,
                title: event.title,
                details: event.details
            )
        }
    }

    private static func parentDeletionTimelineKind(
        _ type: AnimalTimelineEventType
    ) -> ParentDeletionTimelineKind {
        switch type {
        case .birth: return .birth
        case .health: return .health
        case .pregnancy: return .pregnancy
        case .movement: return .movement
        case .status: return .status
        case .tag: return .tag
        }
    }

    private static func multisetCounts<T: Hashable>(_ values: [T]) -> [T: Int] {
        values.reduce(into: [:]) { counts, value in
            counts[value, default: 0] += 1
        }
    }

    private static func didChangeTagColor(
        from before: [AnimalTagSnapshot],
        to after: [AnimalTagSnapshot]
    ) -> Bool {
        before.contains { prior in
            guard let current = after.first(where: { $0.id == prior.id }) else {
                return false
            }
            return current.colorID != prior.colorID
        }
    }
}
