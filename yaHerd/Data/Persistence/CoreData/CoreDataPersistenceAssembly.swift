import Foundation

@MainActor
final class CoreDataTagColorMaterializationCoordinator {
    static let shared = CoreDataTagColorMaterializationCoordinator()

    private struct ReservationKey: Hashable {
        let coordinationID: UUID
        let herdID: UUID
        let colorID: UUID
    }

    private struct DefaultReservationKey: Hashable {
        let coordinationID: UUID
        let herdID: UUID
    }

    private var reservations: Set<ReservationKey> = []
    private var defaultReservations: Set<DefaultReservationKey> = []

    func reserve(
        coordinationID: UUID,
        herdID: UUID,
        colorIDs: Set<UUID>,
        reservesDefaultSlot: Bool = false
    ) throws -> Set<UUID> {
        let requested = Set(colorIDs.map {
            ReservationKey(coordinationID: coordinationID, herdID: herdID, colorID: $0)
        })
        if let conflict = requested.first(where: reservations.contains) {
            throw CoreDataPersistenceError.tagColorMaterializationInProgress(id: conflict.colorID, herdID: conflict.herdID)
        }
        let defaultKey = DefaultReservationKey(coordinationID: coordinationID, herdID: herdID)
        if reservesDefaultSlot, defaultReservations.contains(defaultKey) {
            throw CoreDataPersistenceError.tagColorDefaultMaterializationInProgress(herdID: herdID)
        }
        reservations.formUnion(requested)
        if reservesDefaultSlot {
            defaultReservations.insert(defaultKey)
        }
        return colorIDs
    }

    func assertAvailable(
        coordinationID: UUID,
        herdID: UUID,
        colorIDs: Set<UUID>,
        requiresDefaultSlot: Bool = false
    ) throws {
        if let colorID = colorIDs.first(where: { reservations.contains(ReservationKey(coordinationID: coordinationID, herdID: herdID, colorID: $0)) }) {
            throw CoreDataPersistenceError.tagColorMaterializationInProgress(id: colorID, herdID: herdID)
        }
        if requiresDefaultSlot && defaultReservations.contains(DefaultReservationKey(coordinationID: coordinationID, herdID: herdID)) {
            throw CoreDataPersistenceError.tagColorDefaultMaterializationInProgress(herdID: herdID)
        }
    }

    func release(coordinationID: UUID, herdID: UUID, colorIDs: Set<UUID>, releasesDefaultSlot: Bool = false) {
        for colorID in colorIDs {
            reservations.remove(ReservationKey(coordinationID: coordinationID, herdID: herdID, colorID: colorID))
        }
        if releasesDefaultSlot {
            defaultReservations.remove(DefaultReservationKey(coordinationID: coordinationID, herdID: herdID))
        }
    }
}

enum CoreDataResidentWriteCoordinationError: Error, Equatable {
    case pastureDeletionInProgress
}

final class CoreDataPastureResidentWriteCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var activeAnimalWrites = 0
    private var deletionPending = false
    private var deletionContinuation: CheckedContinuation<Void, Never>?

    func beginAnimalWrite() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !deletionPending else {
            throw CoreDataResidentWriteCoordinationError.pastureDeletionInProgress
        }
        activeAnimalWrites += 1
    }

    func endAnimalWrite() {
        let continuation: CheckedContinuation<Void, Never>?
        lock.lock()
        precondition(activeAnimalWrites > 0)
        activeAnimalWrites -= 1
        if activeAnimalWrites == 0, deletionPending {
            continuation = deletionContinuation
            deletionContinuation = nil
        } else {
            continuation = nil
        }
        lock.unlock()
        continuation?.resume()
    }

    func acquirePastureDeletion() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            precondition(!deletionPending)
            deletionPending = true
            if activeAnimalWrites == 0 {
                lock.unlock()
                continuation.resume()
            } else {
                deletionContinuation = continuation
                lock.unlock()
            }
        }
    }

    func releasePastureDeletion() {
        lock.lock()
        deletionPending = false
        deletionContinuation = nil
        lock.unlock()
    }
}

actor CoreDataAsyncSerialGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

final class CoreDataPersistenceAssembly {
    let persistence: CoreDataPersistentContainer
    let contextFactory: CoreDataContextFactory
    let transactionExecutor: CoreDataTransactionExecutor
    let animalAggregateWriteGate: CoreDataAsyncSerialGate
    let pastureResidentWriteCoordinator: CoreDataPastureResidentWriteCoordinator
    let coordinationID: UUID
    let lookup: CoreDataLookup

    init(persistence: CoreDataPersistentContainer) {
        self.persistence = persistence
        self.contextFactory = CoreDataContextFactory(persistence: persistence)
        self.transactionExecutor = CoreDataTransactionExecutor(contextFactory: contextFactory)
        self.animalAggregateWriteGate = CoreDataAsyncSerialGate()
        self.pastureResidentWriteCoordinator = CoreDataPastureResidentWriteCoordinator()
        self.coordinationID = UUID()
        self.lookup = CoreDataLookup()
    }

    static func load(storeURL: URL, accessMode: CoreDataStoreAccessMode = .readWrite) async throws -> CoreDataPersistenceAssembly {
        CoreDataPersistenceAssembly(persistence: try await CoreDataPersistentContainer.load(storeURL: storeURL, accessMode: accessMode))
    }

    static func inMemory() async throws -> CoreDataPersistenceAssembly {
        CoreDataPersistenceAssembly(persistence: try await CoreDataPersistentContainer.inMemory())
    }
}
