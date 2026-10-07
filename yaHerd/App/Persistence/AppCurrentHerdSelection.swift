import Foundation

@MainActor
final class AppCurrentHerdSelection: CurrentHerdSelectionReading {
    private(set) var currentHerdID: UUID?

    init(currentHerdID: UUID? = nil) {
        self.currentHerdID = currentHerdID
    }

    func select(_ herdID: UUID?) {
        currentHerdID = herdID
    }
}
