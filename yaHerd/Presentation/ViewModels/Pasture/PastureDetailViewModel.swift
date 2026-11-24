import Foundation
import Observation

struct PastureStockingDisplay: Hashable {
    let metrics: PastureMetrics
    let utilizationStatus: PastureUtilizationStatus
    let badge: PastureUtilizationBadge?
}

enum PastureUtilizationBadge: Hashable {
    case overCapacity
    case underutilized

    var title: String {
        switch self {
        case .overCapacity:
            return "Over Capacity"
        case .underutilized:
            return "Underutilized"
        }
    }

    var systemImage: String {
        switch self {
        case .overCapacity:
            return "exclamationmark.triangle.fill"
        case .underutilized:
            return "arrow.down.left.and.arrow.up.right"
        }
    }
}

@MainActor
@Observable
final class PastureDetailViewModel {
    private(set) var detail: PastureDetailSnapshot?
    private(set) var residentAnimals: [AnimalSummary] = []
    let form = PastureFormViewModel()
    var isEditing = false
    var hasLoaded = false
    var errorMessage: String?
    private var editingBaseline: PastureDetailSnapshot?
    private var loadedPastureID: UUID?
    private var lastLoadedRevision: UInt64 = 0

    var navigationTitle: String {
        detail?.name ?? "Pasture"
    }

    var shouldShowStockingSection: Bool {
        if isEditing {
            return form.shouldShowStockingFields
        }

        return PastureStockingPolicy.shouldUseStockingFields(acreage: detail?.acreage)
    }

    var activeAnimalCountText: String {
        guard let detail else { return "Active Animals: 0" }
        return "Active Animals: \(detail.activeAnimalCount)"
    }

    var shouldShowAcreageSummary: Bool {
        PastureStockingPolicy.shouldUseStockingFields(acreage: detail?.acreage)
    }

    var shouldShowUsableAcreageSummary: Bool {
        guard let detail,
              let acreage = detail.acreage,
              let usableAcreage = detail.usableAcreage else {
            return false
        }
        return usableAcreage != acreage
    }

    var stockingDisplay: PastureStockingDisplay? {
        guard let detail else { return nil }
        let metrics = detail.metrics
        return PastureStockingDisplay(
            metrics: metrics,
            utilizationStatus: metrics.utilizationStatus,
            badge: utilizationBadge(for: metrics)
        )
    }

    func observe(
        pastureID: UUID,
        using repository: any PastureDetailRepository,
        mutationStream: any ApplicationMutationStreaming,
        expectedHerdID: UUID?,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) async {
        guard isOriginatingSelectionCurrent(
            expectedHerdID: expectedHerdID,
            expectedSelectionRevision: expectedSelectionRevision,
            selection: selection
        ), !Task.isCancelled else {
            resetForHerdChange()
            return
        }

        let startingRevision = mutationStream.pastureRevision
        if loadedPastureID != pastureID || !hasLoaded || lastLoadedRevision < startingRevision {
            if load(
                pastureID: pastureID, using: repository,
                expectedHerdID: expectedHerdID,
                expectedSelectionRevision: expectedSelectionRevision, selection: selection
            ) {
                lastLoadedRevision = startingRevision
            }
        }

        for await revision in mutationStream.revisions(
            for: .pastures,
            after: lastLoadedRevision
        ) {
            guard !Task.isCancelled,
                  isOriginatingSelectionCurrent(
                    expectedHerdID: expectedHerdID,
                    expectedSelectionRevision: expectedSelectionRevision,
                    selection: selection
                  ) else { return }
            if load(
                pastureID: pastureID, using: repository,
                expectedHerdID: expectedHerdID,
                expectedSelectionRevision: expectedSelectionRevision, selection: selection
            ) {
                lastLoadedRevision = revision
            }
        }
    }

    @discardableResult
    func load(
        pastureID: UUID,
        using repository: any PastureDetailRepository,
        expectedHerdID: UUID?,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) -> Bool {
        guard isOriginatingSelectionCurrent(
            expectedHerdID: expectedHerdID,
            expectedSelectionRevision: expectedSelectionRevision,
            selection: selection
        ) else {
            resetForHerdChange()
            return false
        }
        if loadedPastureID != pastureID {
            resetForPastureChange()
        }
        defer { hasLoaded = true }

        do {
            guard let loadedDetail = try repository.fetchPastureDetail(id: pastureID) else {
                detail = nil
                residentAnimals = []
                errorMessage = "This pasture is no longer available."
                return true
            }
            let residents = try repository.fetchResidentAnimals(pastureID: pastureID)
            detail = loadedDetail
            residentAnimals = residents
            loadedPastureID = pastureID
            errorMessage = nil
            if !isEditing {
                form.populate(from: loadedDetail)
            } else if let baseline = editingBaseline,
                      Self.editableValuesChanged(from: baseline, to: loadedDetail) {
                errorMessage = "This pasture changed on another device. Your draft is retained; reopen the editor before saving."
            }
            return true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }

    func beginEditing(
        expectedHerdID: UUID?,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) {
        guard isOriginatingSelectionCurrent(
            expectedHerdID: expectedHerdID,
            expectedSelectionRevision: expectedSelectionRevision,
            selection: selection
        ) else {
            resetForHerdChange()
            return
        }
        guard let detail else { return }
        editingBaseline = detail
        form.populate(from: detail)
        isEditing = true
    }

    func cancelEditing() {
        editingBaseline = nil
        guard let detail else {
            isEditing = false
            return
        }
        form.populate(from: detail)
        isEditing = false
    }

    func save(
        pastureID: UUID,
        using repository: any PastureDetailEditingRepository,
        expectedHerdID: UUID,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) {
        guard selection.currentHerdID == expectedHerdID,
              selection.selectionRevision == expectedSelectionRevision else {
            return
        }
        guard loadedPastureID == pastureID, detail?.id == pastureID else {
            errorMessage = "The selected pasture changed before this edit could be saved. Please try again."
            return
        }

        do {
            guard let baseline = editingBaseline,
                  let current = try repository.fetchPastureDetail(id: pastureID),
                  !Self.editableValuesChanged(from: baseline, to: current) else {
                errorMessage = "This pasture changed or was removed. Your draft is retained; reopen the editor before saving."
                return
            }
            let input = try form.makeUpdateInput()
            let updated = try UpdatePastureUseCase(repository: repository).execute(
                id: pastureID,
                input: input
            )
            detail = updated
            residentAnimals = try repository.fetchResidentAnimals(pastureID: pastureID)
            loadedPastureID = pastureID
            form.populate(from: updated)
            editingBaseline = nil
            isEditing = false
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func resetForHerdChange() {
        resetForPastureChange()
        lastLoadedRevision = 0
        form.name = ""
        form.acreageText = ""
        form.usableAcreageText = ""
        form.targetAcresPerHeadText = ""
        form.errorMessage = nil
    }

    private func isOriginatingSelectionCurrent(
        expectedHerdID: UUID?,
        expectedSelectionRevision: UInt64,
        selection: AppCurrentHerdSelection
    ) -> Bool {
        guard let expectedHerdID else { return false }
        return selection.currentHerdID == expectedHerdID
            && selection.selectionRevision == expectedSelectionRevision
    }

    private static func editableValuesChanged(
        from baseline: PastureDetailSnapshot, to current: PastureDetailSnapshot
    ) -> Bool {
        baseline.name != current.name ||
            baseline.acreage != current.acreage ||
            baseline.usableAcreage != current.usableAcreage ||
            baseline.targetAcresPerHead != current.targetAcresPerHead
    }

    private func resetForPastureChange() {
        editingBaseline = nil
        detail = nil
        residentAnimals = []
        isEditing = false
        hasLoaded = false
        errorMessage = nil
        loadedPastureID = nil
    }

    private func utilizationBadge(for metrics: PastureMetrics) -> PastureUtilizationBadge? {
        if metrics.isOverCapacity {
            return .overCapacity
        }

        if metrics.isUnderutilized {
            return .underutilized
        }

        return nil
    }
}
