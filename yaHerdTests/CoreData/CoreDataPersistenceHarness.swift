import Foundation
@testable import yaHerd

final class CoreDataPersistenceHarness {
    let directoryURL: URL
    let storeURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yaHerd-CoreDataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        storeURL = directoryURL.appendingPathComponent(CoreDataPersistentContainer.storeFileName)
    }

    deinit {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func makeAssembly(
        accessMode: CoreDataStoreAccessMode = .readWrite
    ) async throws -> CoreDataPersistenceAssembly {
        try await CoreDataPersistenceAssembly.load(
            storeURL: storeURL,
            accessMode: accessMode
        )
    }
}
