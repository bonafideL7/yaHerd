import Foundation

/// Opt-in fixture writer used only by the Animal list's original empty-state actions.
@MainActor
protocol SampleDataSeeding {
    /// Uses the identical selected-Herd predicate as the write transaction.
    func canSeedSampleData() throws -> Bool

    /// Returns false without writing if the selected Herd already has records. The caller supplies its originating Herd ID so a deferred action cannot target a later selection.
    func seedSampleDataIfNeeded(for herdID: UUID) async throws -> Bool
    func seedLargeSampleDataIfNeeded(for herdID: UUID) async throws -> Bool
}
