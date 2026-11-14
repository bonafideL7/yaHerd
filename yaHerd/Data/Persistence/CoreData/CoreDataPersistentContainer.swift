import CloudKit
@preconcurrency import CoreData
import Foundation
import Synchronization

enum CoreDataStoreAccessMode: Equatable, Sendable {
    case readWrite
    case readOnly
}

final class CoreDataPersistentContainer {
    static let modelName = "yaHerdModel"
    static let storeFileName = "yaHerd.sqlite"
    static let sharedStoreFileName = "yaHerd-shared.sqlite"
    // Must match the app's CloudKit capability when that capability is enabled.
    static let cloudKitContainerIdentifier = "iCloud.ltd.yaherd"

    private struct StoreLoadProgress {
        let continuation: CheckedContinuation<Void, Error>
        var remaining: Int
        var firstFailure: CoreDataPersistenceError? = nil
    }

    private let container: NSPersistentContainer
    let accessMode: CoreDataStoreAccessMode
    let storeURL: URL?
    private let cloudKitEventObserver: (any NSObjectProtocol)?

    private init(
        container: NSPersistentContainer,
        accessMode: CoreDataStoreAccessMode,
        storeURL: URL?,
        cloudKitEventObserver: (any NSObjectProtocol)? = nil
    ) {
        self.container = container
        self.accessMode = accessMode
        self.storeURL = storeURL
        self.cloudKitEventObserver = cloudKitEventObserver
    }

    deinit {
        if let cloudKitEventObserver {
            NotificationCenter.default.removeObserver(cloudKitEventObserver)
        }
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

    /// Stage 2 store topology. The existing app continues using its local-only
    /// loader until Herd-qualified reads and every write path can route to the
    /// correct store. Constructing descriptions must never move or modify data.
    static func cloudKitStoreDescriptions(
        privateStoreURL: URL
    ) -> [NSPersistentStoreDescription] {
        let privateStore = NSPersistentStoreDescription(url: privateStoreURL)
        let sharedStore = NSPersistentStoreDescription(
            url: privateStoreURL.deletingLastPathComponent()
                .appendingPathComponent(sharedStoreFileName)
        )

        func configure(
            _ description: NSPersistentStoreDescription,
            scope: CKDatabase.Scope
        ) {
            description.type = NSSQLiteStoreType
            description.shouldAddStoreAsynchronously = true
            description.shouldMigrateStoreAutomatically = false
            description.shouldInferMappingModelAutomatically = false
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
            )
            let options = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainerIdentifier
            )
            options.databaseScope = scope
            description.cloudKitContainerOptions = options
        }

        configure(privateStore, scope: .private)
        configure(sharedStore, scope: .shared)
        return [privateStore, sharedStore]
    }

    /// Loads the existing local SQLite store as the private database and a
    /// separate shared SQLite store. Not used by app startup until all Herd
    /// reads and writes are store-qualified.
    static func loadCloudKit(
        storeURL: URL,
        mirroringEnabled: Bool
    ) async throws -> CoreDataPersistentContainer {
        let descriptions = cloudKitStoreDescriptions(privateStoreURL: storeURL)
        if !mirroringEnabled {
            descriptions.forEach { $0.cloudKitContainerOptions = nil }
        }
        return try await loadCloudKit(storeDescriptions: descriptions)
    }

    /// The same dual-store loading path can be exercised with mirroring disabled
    /// in unsigned simulator tests; production descriptions retain CloudKit options.
    static func loadCloudKit(
        storeDescriptions: [NSPersistentStoreDescription]
    ) async throws -> CoreDataPersistentContainer {
        guard storeDescriptions.count == 2 else {
            throw CoreDataPersistenceError.storeLoadFailed(
                url: nil,
                description: "Both private and shared persistent store descriptions are required."
            )
        }

        // Reject an invalid topology before Core Data opens either store.
        // Loading two descriptions for the same SQLite file could expose an
        // existing private Herd through the shared CloudKit database.
        let privateDescription = storeDescriptions[0]
        let sharedDescription = storeDescriptions[1]
        guard privateDescription.type == NSSQLiteStoreType,
              sharedDescription.type == NSSQLiteStoreType,
              let privateURL = privateDescription.url, privateURL.isFileURL,
              let sharedURL = sharedDescription.url, sharedURL.isFileURL,
              privateURL.standardizedFileURL.resolvingSymlinksInPath()
                != sharedURL.standardizedFileURL.resolvingSymlinksInPath() else {
            throw CoreDataPersistenceError.storeLoadFailed(
                url: sharedDescription.url,
                description: "Private and shared stores require distinct local SQLite files."
            )
        }

        // The second store must be the stable shared sibling of the first.
        // Distinct file URLs alone cannot prevent reversed private/shared
        // descriptions from exporting an existing Herd to the wrong database.
        let expectedSharedURL = privateURL.deletingLastPathComponent()
            .appendingPathComponent(sharedStoreFileName)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard sharedURL.standardizedFileURL.resolvingSymlinksInPath()
            == expectedSharedURL else {
            throw CoreDataPersistenceError.storeLoadFailed(
                url: sharedURL,
                description: "The shared store must use the configured shared SQLite URL."
            )
        }

        let privateOptions = privateDescription.cloudKitContainerOptions
        let sharedOptions = sharedDescription.cloudKitContainerOptions
        let localOnly = privateOptions == nil && sharedOptions == nil
        let cloudKitConfigured =
            privateOptions?.databaseScope == .private
            && sharedOptions?.databaseScope == .shared
            && privateOptions?.containerIdentifier == cloudKitContainerIdentifier
            && sharedOptions?.containerIdentifier == cloudKitContainerIdentifier
        guard localOnly || cloudKitConfigured else {
            throw CoreDataPersistenceError.storeLoadFailed(
                url: sharedURL,
                description: "Private and shared CloudKit scopes must both match the configured container."
            )
        }

        // Different URLs can still point at one physical SQLite file via hard
        // links. A private store must never also be attached as a shared store.
        let fileManager = FileManager.default
        let privateFilePath = privateURL.standardizedFileURL.resolvingSymlinksInPath().path
        let sharedFilePath = sharedURL.standardizedFileURL.resolvingSymlinksInPath().path
        if let privateFileNumber = try? fileManager.attributesOfItem(
            atPath: privateFilePath
        )[.systemFileNumber] as? NSNumber,
           let sharedFileNumber = try? fileManager.attributesOfItem(
            atPath: sharedFilePath
           )[.systemFileNumber] as? NSNumber,
           privateFileNumber == sharedFileNumber {
            throw CoreDataPersistenceError.storeLoadFailed(
                url: sharedURL,
                description: "Private and shared stores must be different physical SQLite files."
            )
        }

        let model = try loadModel()
        let container = NSPersistentCloudKitContainer(
            name: modelName,
            managedObjectModel: model
        )
        container.persistentStoreDescriptions = storeDescriptions

        // Observe real Core Data / iCloud setup, upload and download events
        // only in development. The unsigned simulator tests and Release builds
        // never start the event monitor.
        let eventObserver: (any NSObjectProtocol)?
        #if DEBUG
        eventObserver = cloudKitConfigured
            ? CloudKitDevelopmentEventLog.observe(container: container)
            : nil
        var storesLoaded = false
        defer {
            if !storesLoaded, let eventObserver {
                NotificationCenter.default.removeObserver(eventObserver)
            }
        }
        #else
        eventObserver = nil
        #endif

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let progress = Mutex(StoreLoadProgress(
                continuation: continuation,
                remaining: storeDescriptions.count
            ))

            // Core Data calls this once for each store description. Do not
            // report success after only the private store has finished loading.
            container.loadPersistentStores { description, error in
                progress.withLock { state in
                    if let error, state.firstFailure == nil {
                        state.firstFailure = .storeLoadFailed(
                            url: description.url,
                            description: error.localizedDescription
                        )
                    }
                    state.remaining -= 1
                    guard state.remaining == 0 else { return }
                    if let failure = state.firstFailure {
                        state.continuation.resume(throwing: failure)
                    } else {
                        state.continuation.resume()
                    }
                }
            }
        }

        #if DEBUG
        storesLoaded = true
        if cloudKitConfigured {
            ReliabilityLog.persistenceEvent(
                "icloud-mirroring-active",
                detail: "private-and-shared-stores; watch icloud_transfer events"
            )
        }
        #endif
        return CoreDataPersistentContainer(
            container: container,
            accessMode: .readWrite,
            storeURL: storeDescriptions[0].url,
            cloudKitEventObserver: eventObserver
        )
    }

    #if DEBUG
    /// Explicit, opt-in development validation. Apple's dry-run checks the
    /// compiled model for both mirrored stores without uploading schema records.
    /// This is never called by app startup or included in Release builds.
    func validateCloudKitSchemaDryRun() throws {
        try mirroredCloudKitContainer().initializeCloudKitSchema(options: [.dryRun])
    }

    /// Uploads representative records to initialize the CloudKit DEVELOPMENT
    /// schema. Only call from an explicitly opted-in development-signed test.
    /// Never call during normal app launch or when provisioned for production.
    func initializeDevelopmentCloudKitSchema() throws {
        try mirroredCloudKitContainer().initializeCloudKitSchema(options: [])
    }

    private func mirroredCloudKitContainer() throws -> NSPersistentCloudKitContainer {
        guard let cloudKitContainer = container as? NSPersistentCloudKitContainer,
              cloudKitContainer.persistentStoreDescriptions.count == 2,
              cloudKitContainer.persistentStoreDescriptions.allSatisfy({
                  $0.cloudKitContainerOptions != nil
              }) else {
            throw CoreDataPersistenceError.storeLoadFailed(
                url: storeURL,
                description: "CloudKit schema validation requires mirrored private and shared stores."
            )
        }
        return cloudKitContainer
    }
    #endif

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

#if DEBUG
/// Development-only event visibility for diagnosing whether a local save was
/// exported and whether another installation imported from iCloud. No records,
/// account identifiers, or event payloads are logged.
enum CloudKitDevelopmentEventLog {
    static func operationName(
        for type: NSPersistentCloudKitContainer.EventType
    ) -> String {
        switch type {
        case .setup: "setup"
        case .export: "upload"
        case .import: "download"
        @unknown default: "unknown"
        }
    }

    static func status(endDate: Date?, succeeded: Bool) -> String {
        guard endDate != nil else { return "started" }
        return succeeded ? "succeeded" : "failed"
    }

    static func observe(container: NSPersistentCloudKitContainer) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: nil
        ) { notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            let action = operationName(for: event.type)
            let state = status(endDate: event.endDate, succeeded: event.succeeded)
            let store = event.storeIdentifier
            let eventID = event.identifier.uuidString

            if let error = event.error, event.endDate != nil {
                let failure = error as NSError
                ReliabilityLog.persistence.error(
                    "icloud_transfer action=\(action, privacy: .public) state=failed store=\(store, privacy: .public) event=\(eventID, privacy: .public) error_domain=\(failure.domain, privacy: .public) error_code=\(failure.code) error_description=\(failure.localizedDescription, privacy: .private)"
                )
            } else {
                ReliabilityLog.persistence.notice(
                    "icloud_transfer action=\(action, privacy: .public) state=\(state, privacy: .public) store=\(store, privacy: .public) event=\(eventID, privacy: .public)"
                )
            }
        }
    }
}
#endif
