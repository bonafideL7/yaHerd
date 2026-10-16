import Foundation

/// Opt-in fixture writer used only by the Animal list's original empty-state actions.
@MainActor
protocol SampleDataSeeding {
    /// Uses the identical selected-Herd predicate as the write transaction.
    func canSeedSampleData() throws -> Bool

    /// Returns false without writing if the selected Herd already has records.
    func seedSampleDataIfNeeded() async throws -> Bool
    func seedLargeSampleDataIfNeeded() async throws -> Bool
}
