import CloudKit
@preconcurrency import CoreData
import Foundation
import Synchronization

enum CoreDataStoreAccessMode: Equatable, Sendable {
    case readWrite
    case readOnly
}

/// Local SQLite contents alone cannot establish whether iCloud has finished importing.
enum HerdImportState: Equatable, Sendable {
    case localOnly
    case waiting
    case complete
    case failed
    case accountUnavailable
    case accountChanged

    var blocksHerdAccess: Bool {
        self == .accountUnavailable || self == .accountChanged
    }
}

enum HerdShareMembership: Equatable, Sendable {
    case complete
    case incomplete(missingCount: Int)
}

/// Local cache discovery, not confirmation of server-side delivery.
enum HerdShareDiscovery: Equatable, Sendable {
    case unshared
    case existing(membership: HerdShareMembership)
}

enum CoreDataHerdSharingError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case readOnly
    case notOwned
    case selectionChanged
    case inProgress
    case invalidGraph
    case conflictingMembership
    case incompleteMembership
    case operationFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured: "iCloud sharing is not enabled for this launch."
        case .readOnly: "Sharing is unavailable in read-only recovery."
        case .notOwned: "Only the Herd owner can prepare a share."
        case .selectionChanged: "The selected Herd changed. Open the intended Herd again."
        case .inProgress: "Herd sharing is already in progress. Try again when it finishes."
        case .invalidGraph: "The Herd has inconsistent relationships. Sharing cannot safely proceed."
        case .conflictingMembership: "Records already belong to another share. Sharing cannot safely proceed."
        case .incompleteMembership: "The complete share membership is not yet available. Check iCloud activity and try again."
        case .operationFailed: "iCloud could not prepare the Herd share. Check iCloud activity and try again."
        }
    }
}

/// A value-only snapshot of each operation for one loaded persistent store.
/// An export outcome must never be substituted for an import outcome.
struct CloudStoreActivity: Equatable, Sendable {
    enum Issue: Equatable, Sendable {
        case network
        case permission
        case storageQuota
        case service
    }

    struct Outcome: Equatable, Sendable {
        let startDate: Date
        let endDate: Date?
        let state: HerdImportState
        var issue: Issue? = nil

        func follows(_ previous: Self?) -> Bool {
            guard let previous else { return true }
            return startDate > previous.startDate ||
                (startDate == previous.startDate && previous.endDate == nil && endDate != nil)
        }
    }

    var setup: Outcome?
    var importing: Outcome?
    var exporting: Outcome?
}

/// Application-facing values only; never expose store UUIDs or server errors.
struct CloudStorageActivity: Equatable, Sendable {
    let accessState: HerdImportState
    let owned: CloudStoreActivity?
    let shared: CloudStoreActivity?
}

struct StorageActivitySnapshot: Equatable, Sendable {
    let lastLocalSave: Date?
    let cloud: CloudStorageActivity?
}

/// Tracks store-qualified setup/import/export outcomes for this container lifetime.
private final class HerdImportResults: Sendable {
    private typealias Outcome = CloudStoreActivity.Outcome

    private struct State {
        var imports: [String: Outcome] = [:]
        var setup: [String: Outcome] = [:]
        var exports: [String: Outcome] = [:]
        var accountChanged = false
        var unauthenticatedStores: Set<String> = []
    }

    private let state = Mutex(State())

    func record(_ event: NSPersistentCloudKitContainer.Event) -> Bool {
        let outcome: HerdImportState
        if event.endDate == nil {
            outcome = .waiting
        } else if event.succeeded {
            outcome = .complete
        } else {
            let error = event.error as NSError?
            outcome = error?.domain == CKError.errorDomain &&
                error?.code == CKError.Code.notAuthenticated.rawValue
                ? .accountUnavailable : .failed
        }
        let issue: CloudStoreActivity.Issue?
        if outcome == .failed, let error = event.error as NSError?,
           error.domain == CKError.errorDomain {
            switch error.code {
            case CKError.Code.networkUnavailable.rawValue, CKError.Code.networkFailure.rawValue:
                issue = .network
            case CKError.Code.permissionFailure.rawValue:
                issue = .permission
            case CKError.Code.quotaExceeded.rawValue:
                issue = .storageQuota
            case CKError.Code.serviceUnavailable.rawValue, CKError.Code.requestRateLimited.rawValue,
                 CKError.Code.zoneBusy.rawValue:
                issue = .service
            default:
                issue = nil
            }
        } else {
            issue = nil
        }
        let value = Outcome(
            startDate: event.startDate, endDate: event.endDate, state: outcome, issue: issue
        )
        let storeID = event.storeIdentifier
        return state.withLock { state in
            // Export activity is tracked independently and does not change
            // the startup/selection import gate.
            if event.type == .export {
                guard value.follows(state.exports[storeID]) else { return false }
                state.exports[storeID] = value
                return true
            }
            if event.type == .setup {
                guard value.follows(state.setup[storeID]) else {
                    return false
                }
                state.setup[storeID] = value
                if outcome != .complete {
                    state.imports.removeValue(forKey: storeID)
                }
            } else if event.type == .import {
                guard value.follows(state.imports[storeID]) else { return false }
                state.imports[storeID] = value
            } else {
                return false
            }
            if outcome == .accountUnavailable {
                state.unauthenticatedStores.insert(storeID)
            } else if outcome == .complete {
                state.unauthenticatedStores.remove(storeID)
            }
            return true
        }
    }

    func activity(for identifiers: [String]) -> [String: CloudStoreActivity] {
        state.withLock { state in
            Dictionary(uniqueKeysWithValues: Set(identifiers).map { id in
                (id, CloudStoreActivity(
                    setup: state.setup[id],
                    importing: state.imports[id],
                    exporting: state.exports[id]
                ))
            })
        }
    }

    func invalidateAccount() {
        state.withLock { $0.accountChanged = true }
    }

    func importState(for identifiers: [String?]) -> HerdImportState {
        state.withLock { state in
            if state.accountChanged { return .accountChanged }
            if !state.unauthenticatedStores.isDisjoint(with: identifiers.compactMap { $0 }) {
                return .accountUnavailable
            }
            let outcomes: [HerdImportState] = identifiers.map { id in
                guard let id else { return .waiting }
                let setup = state.setup[id]?.state
                if let setup, setup != .complete { return setup }
                return state.imports[id]?.state ?? .waiting
            }
            if outcomes.contains(.accountUnavailable) { return .accountUnavailable }
            if outcomes.contains(.failed) { return .failed }
            return !outcomes.isEmpty && outcomes.allSatisfy { $0 == .complete }
                ? .complete : .waiting
        }
    }
}

final class CoreDataPersistentContainer {
    static let modelName = "yaHerdModel"
    static let storeFileName = "yaHerd.sqlite"
    static let sharedStoreFileName = "yaHerd-shared.sqlite"
    static let remoteStoreChangeNotification = Notification.Name.NSPersistentStoreRemoteChange
    static let herdImportStateChanged = Notification.Name("yaHerd.herdImportStateChanged")
    static let storageActivityChanged = Notification.Name("yaHerd.storageActivityChanged")
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
    private let accountObserver: (any NSObjectProtocol)?
    private let importResults: HerdImportResults?
    let historyWakeups: CoreDataHistoryWakeups?
    private let historyObserver: (any NSObjectProtocol)?

    var cloudStoreActivity: [String: CloudStoreActivity] {
        let identifiers = container.persistentStoreCoordinator.persistentStores.compactMap { store -> String? in
            store.identifier
        }
        return importResults?.activity(for: identifiers) ?? [:]
    }

    var cloudStorageActivity: CloudStorageActivity? {
        guard importResults != nil else { return nil }
        let stores = container.persistentStoreCoordinator.persistentStores
        let activitiesByID = cloudStoreActivity
        func activity(for fileName: String) -> CloudStoreActivity? {
            guard let store = stores.first(where: { $0.url?.lastPathComponent == fileName }) else {
                return nil
            }
            let identifier: String? = store.identifier
            guard let identifier else { return nil }
            return activitiesByID[identifier]
        }
        return CloudStorageActivity(
            accessState: herdImportState,
            owned: activity(for: Self.storeFileName),
            shared: activity(for: Self.sharedStoreFileName)
        )
    }

    var herdImportState: HerdImportState {
        guard let importResults else { return .localOnly }
        return importResults.importState(for: container.persistentStoreCoordinator.persistentStores.map(\.identifier))
    }

    private init(
        container: NSPersistentContainer,
        accessMode: CoreDataStoreAccessMode,
        storeURL: URL?,
        cloudKitEventObserver: (any NSObjectProtocol)? = nil,
        accountObserver: (any NSObjectProtocol)? = nil,
        importResults: HerdImportResults? = nil,
        historyWakeups: CoreDataHistoryWakeups? = nil,
        historyObserver: (any NSObjectProtocol)? = nil
    ) {
        self.container = container
        self.accessMode = accessMode
        self.storeURL = storeURL
        self.cloudKitEventObserver = cloudKitEventObserver
        self.accountObserver = accountObserver
        self.importResults = importResults
        self.historyWakeups = historyWakeups
        self.historyObserver = historyObserver
    }

    deinit {
        if let historyObserver {
            NotificationCenter.default.removeObserver(historyObserver)
        }
        historyWakeups?.finish()
        if let accountObserver {
            NotificationCenter.default.removeObserver(accountObserver)
        }
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

        // Subscribe before store loading so the first setup/import events are
        // captured even when the initial import completes before the chooser opens.
        let importResults = cloudKitConfigured ? HerdImportResults() : nil
        let historyWakeups = cloudKitConfigured ? CoreDataHistoryWakeups() : nil
        // Notifications are scoped to this exact coordinator. They are wakeups,
        // never checkpoint boundaries: each drain checks both store identities.
        let historyObserver = historyWakeups.map { wakeups in
            NotificationCenter.default.addObserver(
                forName: remoteStoreChangeNotification,
                object: container.persistentStoreCoordinator,
                queue: nil
            ) { _ in
                wakeups.requestProcessing()
            }
        }
        let eventObserver = importResults.map { results in
            NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: container, queue: nil
            ) { notification in
                guard let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event else { return }
                #if DEBUG
                CloudKitDevelopmentEventLog.record(event)
                #endif
                if results.record(event) {
                    NotificationCenter.default.post(name: CoreDataPersistentContainer.storageActivityChanged, object: nil)
                    // Export progress is informational; it must not trigger
                    // an import gate change or an artificial data mutation.
                    guard event.type != .export else { return }
                    NotificationCenter.default.post(name: CoreDataPersistentContainer.herdImportStateChanged, object: nil)
                    // Even a failed import may have committed some transactions.
                    // A setup/import completion is a second chance to catch up.
                    if event.endDate != nil {
                        historyWakeups?.requestProcessing()
                    }
                }
            }
        }
        // A changed account is not the same as a transient network failure.
        // Stop exposing this session's mirrored records until stores can be
        // opened for the new account; full account isolation is a later stage.
        let accountObserver = importResults.map { results in
            NotificationCenter.default.addObserver(
                forName: .CKAccountChanged, object: nil, queue: nil
            ) { _ in
                results.invalidateAccount()
                NotificationCenter.default.post(name: CoreDataPersistentContainer.herdImportStateChanged, object: nil)
                NotificationCenter.default.post(name: CoreDataPersistentContainer.storageActivityChanged, object: nil)
            }
        }
        var storesLoaded = false
        defer {
            if !storesLoaded {
                if let eventObserver { NotificationCenter.default.removeObserver(eventObserver) }
                if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
                if let historyObserver { NotificationCenter.default.removeObserver(historyObserver) }
                historyWakeups?.finish()
            }
        }

        do {
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
        } catch {
            // All load callbacks have finished. A partially opened topology
            // must not remain attached while read-only recovery inspects disk.
            do {
                try detachStores(from: container)
            } catch {
                ReliabilityLog.persistenceSaveFailure("partial-store-detach", error: error)
            }
            throw error
        }

        storesLoaded = true
        #if DEBUG
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
            cloudKitEventObserver: eventObserver,
            accountObserver: accountObserver,
            importResults: importResults,
            historyWakeups: historyWakeups,
            historyObserver: historyObserver
        )
    }

    private static func detachStores(from container: NSPersistentContainer) throws {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }

    #if DEBUG
    /// An explicitly requested development-only operation against disposable
    /// stores. The user's private and shared SQLite files are never opened.
    static func runDevelopmentSchemaValidation(initialize: Bool) async throws {
        #if YAHERD_ICLOUD_DEVELOPMENT
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("yaHerd-schema-" + UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let probe = try await loadCloudKit(
            storeURL: directory.appendingPathComponent(storeFileName),
            mirroringEnabled: true
        )
        defer {
            // Never remove SQLite files while a coordinator still owns them.
            do {
                try detachStores(from: probe.container)
                try fileManager.removeItem(at: directory)
            } catch {
                ReliabilityLog.persistenceSaveFailure("schema-probe-cleanup", error: error)
            }
        }
        try probe.validateCloudKitSchemaDryRun()
        if initialize {
            try probe.initializeDevelopmentCloudKitSchema()
        }
        #else
        throw CoreDataPersistenceError.storeLoadFailed(
            url: nil,
            description: "Schema validation requires the iCloud Development build configuration."
        )
        #endif
    }

    /// Apple's dry-run checks the compiled model without uploading schema records.
    func validateCloudKitSchemaDryRun() throws {
        try mirroredCloudKitContainer().initializeCloudKitSchema(options: [.dryRun])
    }

    /// Uploads representative records to initialize the CloudKit DEVELOPMENT
    /// schema. Only call from the explicitly opted-in development scheme.
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
        if storeType == NSSQLiteStoreType {
            // This is the same physical private SQLite store used by CloudKit.
            // Once opened with persistent history, later local-only launches
            // must retain this option or Core Data forces it read-only.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(
                true as NSNumber,
                forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
            )
        }
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

    /// Sharing uses the actual configured private store, not the filename or
    /// a UUID-only lookup. A joined share must never be recreated as owned.
    private func ownedSharingContainer(for root: CDHerd) throws -> NSPersistentCloudKitContainer {
        guard accessMode == .readWrite else {
            throw CoreDataHerdSharingError.readOnly
        }
        guard importResults != nil,
              let mirrored = container as? NSPersistentCloudKitContainer else {
            throw CoreDataHerdSharingError.notConfigured
        }
        guard !herdImportState.blocksHerdAccess else {
            throw HerdRepositoryError.accountUnavailable
        }
        guard let privateURL = storeURL,
              let store = root.objectID.persistentStore,
              !root.objectID.isTemporaryID,
              store.url == privateURL,
              container.persistentStoreCoordinator.persistentStores.contains(where: { $0 === store }),
              container.persistentStoreDescriptions.contains(where: {
                  $0.url == privateURL && $0.cloudKitContainerOptions?.databaseScope == .private
              }) else {
            throw CoreDataHerdSharingError.notOwned
        }
        return mirrored
    }

    /// Called on the root's context queue. Check the graph before asking
    /// CloudKit to traverse it: a malformed cross-Herd link must not disclose
    /// another Herd's records through native deep traversal.
    func inspectOwnedShare(root: CDHerd, objects: [NSManagedObject]) throws -> HerdShareDiscovery {
        let mirrored = try ownedSharingContainer(for: root)
        return try Self.inspectShare(root: root, objects: objects, in: mirrored).discovery
    }

    private static func inspectShare(
        root: CDHerd,
        objects: [NSManagedObject],
        in mirrored: NSPersistentCloudKitContainer
    ) throws -> (discovery: HerdShareDiscovery, share: CKShare?) {
        let ids = objects.map(\.objectID)
        let shares = try mirrored.fetchShares(matching: ids)
        let rootShare = shares[root.objectID]
        // Refuse to adopt a child from any other share, including a share
        // for which the root has no locally known association.
        guard shares.values.allSatisfy({ $0.recordID == rootShare?.recordID }) else {
            throw CoreDataHerdSharingError.conflictingMembership
        }
        guard let rootShare else {
            return (.unshared, nil)
        }
        guard rootShare.currentUserParticipant?.role == .owner,
              rootShare.currentUserParticipant?.acceptanceStatus == .accepted else {
            throw CoreDataHerdSharingError.notOwned
        }
        let missing = ids.filter { shares[$0] == nil }.count
        return (.existing(membership: missing == 0 ? .complete : .incomplete(missingCount: missing)), rootShare)
    }

    /// Native sharing migrates the connected graph to one share zone. New
    /// children maintain a direct Herd relationship and Core Data assigns
    /// their zone through its mirroring delegate. Reinspect membership when
    /// preparing a share again; never create a second share for that root.
    func prepareOwnedShare(
        root: CDHerd,
        objects: [NSManagedObject],
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) throws {
        let mirrored = try ownedSharingContainer(for: root)
        let existing = try Self.inspectShare(root: root, objects: objects, in: mirrored)
        if case .existing = existing.discovery {
            // An incomplete cache can reflect unsent children. Do not force
            // a zone move or recreate a share while mirroring catches up.
            completion(.success(()))
            return
        }
        let expectedIDs = Set(objects.map(\.objectID))
        // A nil share creates a private zone with no invited participants.
        // Invitation visibility and permission configuration are Stage 5.3.
        mirrored.share(objects, to: nil) { ids, share, _, error in
            if let error {
                let failure = error as NSError
                ReliabilityLog.persistence.error(
                    "operation=herd-share-create domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)"
                )
                completion(.failure(CoreDataHerdSharingError.operationFailed))
            } else if let ids, share != nil, expectedIDs.isSubset(of: ids) {
                completion(.success(()))
            } else {
                // Do not purge or create again: a share may already exist.
                completion(.failure(CoreDataHerdSharingError.incompleteMembership))
            }
        }
    }

    /// Read only the shares already imported by this container. This does not
    /// contact the server or establish current authorization while offline.
    func sharingMetadata(for objectIDs: [NSManagedObjectID]) -> [NSManagedObjectID: HerdSharingMetadata] {
        guard !objectIDs.isEmpty else { return [:] }
        guard importResults != nil,
              let mirrored = container as? NSPersistentCloudKitContainer else {
            return Dictionary(uniqueKeysWithValues: objectIDs.map { ($0, .notConfigured) })
        }
        guard !herdImportState.blocksHerdAccess else {
            return Dictionary(uniqueKeysWithValues: objectIDs.map { ($0, .unavailable) })
        }

        // Read each store independently so a failed shared-store metadata
        // lookup cannot hide successfully loaded owned-share information.
        let groups = Dictionary(grouping: objectIDs, by: { $0.persistentStore })
        var metadata: [NSManagedObjectID: HerdSharingMetadata] = [:]
        for (store, ids) in groups {
            guard store != nil else {
                for id in ids { metadata[id] = .unavailable }
                continue
            }
            do {
                let shares = try mirrored.fetchShares(matching: ids)
                for id in ids {
                    metadata[id] = shares[id].map(Self.sharingMetadata(for:)) ?? .noCachedShare
                }
            } catch {
                let failure = error as NSError
                ReliabilityLog.persistence.error(
                    "operation=share-metadata-read domain=\(failure.domain, privacy: .public) code=\(failure.code, privacy: .public)"
                )
                for id in ids { metadata[id] = .unavailable }
            }
        }
        return metadata
    }

    private static func sharingMetadata(for share: CKShare) -> HerdSharingMetadata {
        let access: HerdSharingMetadata.Access
        if let participant = share.currentUserParticipant {
            switch participant.acceptanceStatus {
            case .removed: access = .removed
            case .pending: access = .pending
            case .accepted:
                if participant.role == .owner {
                    access = .owner
                } else {
                    switch participant.permission {
                    case .readOnly: access = .readOnly
                    case .readWrite: access = .readWrite
                    default: access = .unknown
                    }
                }
            default: access = .unknown
            }
        } else {
            access = .unknown
        }

        // A participant is not guaranteed to see the owner's entire roster.
        // Counts are therefore only meaningful for the current share owner.
        let guests = share.participants.filter { $0.role != .owner }
        return .shared(
            access: access,
            acceptedParticipants: access == .owner
                ? guests.filter { $0.acceptanceStatus == .accepted }.count : nil,
            pendingInvitations: access == .owner
                ? guests.filter { $0.acceptanceStatus == .pending }.count : nil
        )
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

    static func record(_ event: NSPersistentCloudKitContainer.Event) {
        let action = operationName(for: event.type)
        let state = status(endDate: event.endDate, succeeded: event.succeeded)
        let store = event.storeIdentifier
        let eventID = event.identifier.uuidString

        if let error = event.error, event.endDate != nil {
            let failure = error as NSError
            ReliabilityLog.persistence.error(
                "icloud_transfer action=\(action, privacy: .public) state=failed store=\(store, privacy: .public) event=\(eventID, privacy: .public) error_domain=\(failure.domain, privacy: .public) error_code=\(failure.code)"
            )
            // Development console output is intentionally minimal so
            // testers can identify failed transfers without OSLog filters.
            NSLog("yaHerd iCloud %@ failed (error %@/%ld)",
                  action, failure.domain, failure.code)
        } else {
            ReliabilityLog.persistence.notice(
                "icloud_transfer action=\(action, privacy: .public) state=\(state, privacy: .public) store=\(store, privacy: .public) event=\(eventID, privacy: .public)"
            )
            NSLog("yaHerd iCloud %@ %@", action, state)
        }
    }
}
#endif
