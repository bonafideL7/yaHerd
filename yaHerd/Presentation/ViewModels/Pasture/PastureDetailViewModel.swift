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

    func load(pastureID: UUID, using repository: any PastureDetailRepository) {
        defer { hasLoaded = true }

        do {
            let loadedDetail = try LoadPastureDetailUseCase(repository: repository).execute(id: pastureID)
            detail = loadedDetail
            residentAnimals = try repository.fetchResidentAnimals(pastureID: pastureID)
            if !isEditing {
                form.populate(from: loadedDetail)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginEditing() {
        guard let detail else { return }
        form.populate(from: detail)
        isEditing = true
    }

    func cancelEditing() {
        guard let detail else {
            isEditing = false
            return
        }
        form.populate(from: detail)
        isEditing = false
    }

    func save(pastureID: UUID, using repository: any PastureUpdateRepository & PastureResidentAnimalReader) {
        do {
            let input = try form.makeUpdateInput()
            let updated = try UpdatePastureUseCase(repository: repository).execute(
                id: pastureID,
                input: input
            )
            detail = updated
            residentAnimals = try repository.fetchResidentAnimals(pastureID: pastureID)
            form.populate(from: updated)
            isEditing = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
