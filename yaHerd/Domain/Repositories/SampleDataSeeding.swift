import Foundation

/// Opt-in fixture writer used only by the Animal list's original empty-state actions.
@MainActor
protocol SampleDataSeeding {
    /// Uses the identical selected-Herd predicate as the write transaction.
    func canSeedSampleData() throws -> Bool

    /// Returns false without writing if the selected Herd already has records.
    /// Capture the originating Herd and selection revision so an old request
    /// cannot resume after switching away and back to the same Herd.
    func seedSampleDataIfNeeded(for herdID: UUID, selectionRevision: UInt64) async throws -> Bool
    func seedLargeSampleDataIfNeeded(for herdID: UUID, selectionRevision: UInt64) async throws -> Bool
}
