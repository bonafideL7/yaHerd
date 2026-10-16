import Foundation

/// Opt-in fixture writer used only by the Animal list's original empty-state actions.
@MainActor
protocol SampleDataSeeding {
    /// Returns false without writing if the selected Herd already has records.
    func seedSampleDataIfNeeded() async throws -> Bool
    func seedLargeSampleDataIfNeeded() async throws -> Bool
}
