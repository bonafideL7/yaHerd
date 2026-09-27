@preconcurrency import CoreData
import Foundation

enum CoreDataStoreAccessMode: Equatable, Sendable {
    case readWrite
    case readOnly
}

final class CoreDataPersistentContainer {
    static let modelName = "yaHerdModel"
    static let storeFileName = "yaHerd.sqlite"

    private let container: NSPersistentContainer
    let accessMode: CoreDataStoreAccessMode
    let storeURL: URL?

    private init(
        container: NSPersistentContainer,
        accessMode: CoreDataStoreAccessMode,
        storeURL: URL?
    ) {
        self.container = container
        self.accessMode = accessMode
        self.storeURL = storeURL
    }

    static func load(
        storeURL: URL,
        accessMode: CoreDataStoreAccessMode = .readWrite
    ) async throws -> CoreDataPersistentContainer {
        try await load(
            storeURL: storeURL,
            storeType: NSSQLiteStoreType,
            accessMode: accessMode
        )
    }

    static func inMemory() async throws -> CoreDataPersistentContainer {
        try await load(
            storeURL: nil,
            storeType: NSInMemoryStoreType,
            accessMode: .readWrite
        )
    }

    static func defaultStoreURL(
        fileManager: FileManager = .default
    ) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("yaHerd", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent(storeFileName)
    }

    private static func load(
        storeURL: URL?,
        storeType: String,
        accessMode: CoreDataStoreAccessMode
    ) async throws -> CoreDataPersistentContainer {
        let model = try loadModel()
        let container = NSPersistentContainer(name: modelName, managedObjectModel: model)

        let description: NSPersistentStoreDescription
        if let storeURL {
            description = NSPersistentStoreDescription(url: storeURL)
        } else {
            description = NSPersistentStoreDescription()
        }
        description.type = storeType
        description.shouldAddStoreAsynchronously = true
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        if accessMode == .readOnly {
            description.setOption(true as NSNumber, forKey: NSReadOnlyPersistentStoreOption)
        }
        container.persistentStoreDescriptions = [description]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(
                        throwing: CoreDataPersistenceError.storeLoadFailed(
                            url: storeURL,
                            description: error.localizedDescription
                        )
                    )
                } else {
                    continuation.resume()
                }
            }
        }

        let loadedStoreURL = container.persistentStoreCoordinator.persistentStores.first?.url
        return CoreDataPersistentContainer(
            container: container,
            accessMode: accessMode,
            storeURL: loadedStoreURL ?? storeURL
        )
    }

    var persistentStoreCoordinator: NSPersistentStoreCoordinator {
        container.persistentStoreCoordinator
    }

    func makeBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }

    private static func loadModel() throws -> NSManagedObjectModel {
        let bundle = Bundle(for: CDHerd.self)
        let url = bundle.url(forResource: modelName, withExtension: "momd")
            ?? bundle.url(forResource: modelName, withExtension: "mom")

        guard let url, let model = NSManagedObjectModel(contentsOf: url) else {
            throw CoreDataPersistenceError.modelNotFound(name: modelName)
        }
        return model
    }
}
