import Foundation

/// The single in-memory authority for the Herd used by every repository.
/// Changes must be validated against current store discovery before any
/// Herd-bound UI or repository context is switched.
@MainActor
final class AppCurrentHerdSelection: CurrentHerdSelectionReading {
    private(set) var currentHerdID: UUID?

    init(currentHerdID: UUID? = nil) {
        self.currentHerdID = currentHerdID
    }

    /// Used by startup after resolving the initial Herd. Runtime switching
    /// must use selectAccessibleHerd so an unavailable root cannot be selected.
    func select(_ herdID: UUID?) {
        currentHerdID = herdID
    }

    /// Validate on a fresh store read; never trust a cached picker result.
    /// Both the repository scope and navigation switch together on MainActor,
    /// with no suspension point. Any lookup error preserves the prior state.
    @discardableResult
    func selectAccessibleHerd(
        _ herdID: UUID,
        using repository: any HerdRepository,
        navigation: AppNavigationState
    ) throws -> HerdSummary {
        let matching = try repository.fetchAccessibleHerds().filter { $0.id == herdID }
        guard !matching.isEmpty else {
            throw HerdRepositoryError.missingHerd
        }
        guard matching.count == 1 else {
            throw HerdSelectionError.ambiguousHerdID(herdID)
        }

        navigation.resetForHerdChange(to: herdID)
        currentHerdID = herdID
        return matching[0].summary
    }
}

enum HerdSelectionError: LocalizedError, Equatable {
    case ambiguousHerdID(UUID)

    var errorDescription: String? {
        switch self {
        case .ambiguousHerdID:
            "More than one Herd has the same identifier. Selection has not changed."
        }
    }
}
