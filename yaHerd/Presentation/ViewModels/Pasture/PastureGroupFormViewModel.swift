import Foundation
import Observation

@MainActor
@Observable
final class PastureGroupFormViewModel {
    var name = ""
    var grazeDays = 7
    var restDays = 21
    var errorMessage: String?

    var canSave: Bool {
        PastureGroupInputValidator.canAttemptSave(
            name: name,
            grazeDays: grazeDays,
            restDays: restDays
        )
    }

    func populate(from detail: PastureGroupDetailSnapshot) {
        name = detail.name
        grazeDays = detail.grazeDays
        restDays = detail.restDays
        errorMessage = nil
    }

    func create(
        using repository: any PastureGroupCreateRepository,
        expectedHerdID: UUID,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) throws {
        try validateSelection(
            expectedHerdID: expectedHerdID,
            expectedSelectionRevision: expectedSelectionRevision,
            selection: selection
        )
        _ = try CreatePastureGroupUseCase(repository: repository).execute(
            name: name,
            grazeDays: grazeDays,
            restDays: restDays
        )
    }

    func update(
        id: UUID,
        using repository: any PastureGroupUpdateRepository,
        expectedHerdID: UUID,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) throws {
        try validateSelection(
            expectedHerdID: expectedHerdID,
            expectedSelectionRevision: expectedSelectionRevision,
            selection: selection
        )
        _ = try UpdatePastureGroupUseCase(repository: repository).execute(
            id: id,
            name: name,
            grazeDays: grazeDays,
            restDays: restDays
        )
    }

    private func validateSelection(
        expectedHerdID: UUID,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) throws {
        guard selection.currentHerdID == expectedHerdID,
              selection.selectionRevision == expectedSelectionRevision else {
            throw CancellationError()
        }
    }
}
