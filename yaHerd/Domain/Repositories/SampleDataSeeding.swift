import Foundation

@MainActor
protocol SampleDataSeeding {
    func seedSampleDataIfNeeded()
    func seedLargeSampleDataIfNeeded()
}
