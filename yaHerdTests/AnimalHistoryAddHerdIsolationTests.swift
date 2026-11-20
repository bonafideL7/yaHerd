import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class AnimalHistoryAddHerdIsolationTests: XCTestCase {
    func testHealthRecordSaveRejectsChangedOrRevokedHerdSelection() {
        for change in SelectionChange.allCases {
            let herdID = UUID()
            let selection = AppCurrentHerdSelection(currentHerdID: herdID)
            let revision = selection.selectionRevision
            let repository = HealthRecordWriteProbe()
            let model = HealthRecordAddViewModel()
            model.treatment = "Treatment"

            change.apply(to: selection, originalHerdID: herdID)

            XCTAssertFalse(
                model.save(
                    animalID: UUID(),
                    using: repository,
                    expectedHerdID: herdID,
                    expectedSelectionRevision: revision,
                    selection: selection
                ),
                "Unexpected health-record save for \(change)"
            )
            XCTAssertEqual(repository.saveCount, 0, "Wrong-Herd health-record write for \(change)")
        }
    }

    func testPregnancyCheckSaveRejectsChangedOrRevokedHerdSelection() {
        for change in SelectionChange.allCases {
            let herdID = UUID()
            let selection = AppCurrentHerdSelection(currentHerdID: herdID)
            let revision = selection.selectionRevision
            let repository = PregnancyCheckWriteProbe()
            let model = PregnancyCheckAddViewModel()

            change.apply(to: selection, originalHerdID: herdID)

            XCTAssertFalse(
                model.save(
                    animalID: UUID(),
                    using: repository,
                    expectedHerdID: herdID,
                    expectedSelectionRevision: revision,
                    selection: selection
                ),
                "Unexpected pregnancy-check save for \(change)"
            )
            XCTAssertEqual(repository.saveCount, 0, "Wrong-Herd pregnancy-check write for \(change)")
        }
    }

    func testHealthRecordSaveInUnchangedHerdReachesRepository() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let repository = HealthRecordWriteProbe()
        let model = HealthRecordAddViewModel()
        model.treatment = "Treatment"

        XCTAssertFalse(
            model.save(
                animalID: UUID(),
                using: repository,
                expectedHerdID: herdID,
                expectedSelectionRevision: selection.selectionRevision,
                selection: selection
            )
        )
        XCTAssertEqual(repository.saveCount, 1)
    }

    func testPregnancyCheckSaveInUnchangedHerdReachesRepository() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let repository = PregnancyCheckWriteProbe()
        let model = PregnancyCheckAddViewModel()

        XCTAssertFalse(
            model.save(
                animalID: UUID(),
                using: repository,
                expectedHerdID: herdID,
                expectedSelectionRevision: selection.selectionRevision,
                selection: selection
            )
        )
        XCTAssertEqual(repository.saveCount, 1)
    }
}

@MainActor
private enum SelectionChange: CaseIterable {
    case differentHerd
    case roundTrip
    case revoked

    func apply(to selection: AppCurrentHerdSelection, originalHerdID: UUID) {
        switch self {
        case .differentHerd:
            selection.select(UUID())
        case .roundTrip:
            selection.select(UUID())
            selection.select(originalHerdID)
        case .revoked:
            selection.select(nil)
        }
    }
}

@MainActor
private final class HealthRecordWriteProbe: AnimalHealthRecordAdding {
    private(set) var saveCount = 0

    func addHealthRecord(animalID: UUID, input: HealthRecordInput) throws -> AnimalDetailSnapshot {
        saveCount += 1
        throw ProbeFailure.attempted
    }
}

@MainActor
private final class PregnancyCheckWriteProbe: AnimalPregnancyCheckAdding {
    private(set) var saveCount = 0

    func addPregnancyCheck(animalID: UUID, input: PregnancyCheckInput) throws -> AnimalDetailSnapshot {
        saveCount += 1
        throw ProbeFailure.attempted
    }
}

private enum ProbeFailure: Error {
    case attempted
}
