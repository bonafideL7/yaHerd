import Dispatch
import Foundation
import Synchronization

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

@MainActor
final class CoreDataPastureResidentWriteCoordinator {
    private var activeConflictingWrites = 0
    private var deletionPending = false
    private var animalDrainContinuation: CheckedContinuation<Void, Never>?
    private var deletionWaiters: [CheckedContinuation<Void, Never>] = []

    func beginAnimalWrite() throws {
        try beginConflictingWrite()
    }

    func endAnimalWrite() {
        endConflictingWrite()
    }

    func beginPastureWrite() throws {
        try beginConflictingWrite()
    }

    func endPastureWrite() {
        endConflictingWrite()
    }

    func beginFieldCheckWrite() throws {
        try beginConflictingWrite()
    }

    func endFieldCheckWrite() {
        endConflictingWrite()
    }

    func beginWorkingWrite() throws {
        try beginConflictingWrite()
    }

    func endWorkingWrite() {
        endConflictingWrite()
    }

    private func beginConflictingWrite() throws {
        guard !deletionPending else {
            throw CoreDataResidentWriteCoordinationError.pastureDeletionInProgress
        }
        activeConflictingWrites += 1
    }

    private func endConflictingWrite() {
        precondition(activeConflictingWrites > 0)
        activeConflictingWrites -= 1
        if activeConflictingWrites == 0, deletionPending {
            let continuation = animalDrainContinuation
            animalDrainContinuation = nil
            continuation?.resume()
        }
    }

    func acquirePastureDeletion() async {
        if deletionPending {
            await withCheckedContinuation { continuation in
                deletionWaiters.append(continuation)
            }
            return
        }

        deletionPending = true
        guard activeConflictingWrites > 0 else {
            return
        }
        await withCheckedContinuation { continuation in
            animalDrainContinuation = continuation
        }
    }

    func releasePastureDeletion() {
        animalDrainContinuation = nil
        if deletionWaiters.isEmpty {
            deletionPending = false
        } else {
            deletionWaiters.removeFirst().resume()
        }
    }
}

enum CoreDataAnimalWriteBoundaryError: LocalizedError, Equatable {
    case fieldCheckPending

    var errorDescription: String? {
        switch self {
        case .fieldCheckPending:
            return "A pasture check is already waiting to update animal data. Try this Animal change again after the check finishes."
        }
    }
}

final class CoreDataAnimalWriteBoundary: Sendable {
    private struct State: ~Copyable {
        var activeAnimalWriters = 0
        var fieldCheckActive = false
        var fieldCheckPending = false
        var fieldCheckWaiter: CheckedContinuation<Void, Never>?
        var synchronousAnimalWaiters: [DispatchSemaphore] = []
        var asynchronousAnimalWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    var queuedWriterCount: Int {
        state.withLock {
            $0.synchronousAnimalWaiters.count
                + $0.asynchronousAnimalWaiters.count
        }
    }

    var hasPendingFieldCheck: Bool {
        state.withLock { $0.fieldCheckPending }
    }

    func beginAnimalWriteSynchronously() throws {
        let waiter = DispatchSemaphore(value: 0)
        let shouldWait = try state.withLock { state in
            guard !state.fieldCheckPending else {
                throw CoreDataAnimalWriteBoundaryError.fieldCheckPending
            }
            guard !state.fieldCheckActive else {
                state.synchronousAnimalWaiters.append(waiter)
                return true
            }

            state.activeAnimalWriters += 1
            return false
        }

        if shouldWait {
            waiter.wait()
        }
    }

    func beginAnimalWrite() async {
        let startsImmediately = state.withLock { state in
            guard !state.fieldCheckActive && !state.fieldCheckPending else {
                return false
            }
            state.activeAnimalWriters += 1
            return true
        }
        guard !startsImmediately else {
            return
        }

        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = state.withLock { state in
                guard !state.fieldCheckActive && !state.fieldCheckPending else {
                    state.asynchronousAnimalWaiters.append(continuation)
                    return false
                }
                state.activeAnimalWriters += 1
                return true
            }
            if shouldResumeImmediately {
                continuation.resume()
            }
        }
    }

    func endAnimalWrite() {
        let fieldCheckWaiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            precondition(state.activeAnimalWriters > 0)
            state.activeAnimalWriters -= 1
            guard state.activeAnimalWriters == 0,
                  state.fieldCheckPending,
                  let waiter = state.fieldCheckWaiter else {
                return nil
            }

            state.fieldCheckPending = false
            state.fieldCheckActive = true
            state.fieldCheckWaiter = nil
            return waiter
        }
        fieldCheckWaiter?.resume()
    }

    func acquireFieldCheck() async {
        await withCheckedContinuation { continuation in
            let startsImmediately = state.withLock { state in
                precondition(!state.fieldCheckActive && !state.fieldCheckPending)
                guard state.activeAnimalWriters == 0 else {
                    state.fieldCheckPending = true
                    state.fieldCheckWaiter = continuation
                    return false
                }

                state.fieldCheckActive = true
                return true
            }

            if startsImmediately {
                continuation.resume()
            }
        }
    }

    func releaseFieldCheck() {
        let waiters = state.withLock { state -> (
            [DispatchSemaphore],
            [CheckedContinuation<Void, Never>]
        ) in
            precondition(state.fieldCheckActive)
            state.fieldCheckActive = false

            let synchronous = state.synchronousAnimalWaiters
            let asynchronous = state.asynchronousAnimalWaiters
            state.synchronousAnimalWaiters.removeAll(keepingCapacity: true)
            state.asynchronousAnimalWaiters.removeAll(keepingCapacity: true)
            state.activeAnimalWriters += synchronous.count + asynchronous.count
            return (synchronous, asynchronous)
        }

        for waiter in waiters.0 {
            waiter.signal()
        }
        for waiter in waiters.1 {
            waiter.resume()
        }
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
    let contextFactory: CoreDataContextFactory
    let transactionExecutor: CoreDataTransactionExecutor
    let animalWriteBoundary: CoreDataAnimalWriteBoundary
    let animalAggregateWriteGate: CoreDataAsyncSerialGate
    let fieldCheckWriteGate: CoreDataAsyncSerialGate
    let workingWriteGate: CoreDataAsyncSerialGate
    let pastureResidentWriteCoordinator: CoreDataPastureResidentWriteCoordinator
    let coordinationID: UUID
    let lookup: CoreDataLookup

    init(persistence: sending CoreDataPersistentContainer) {
        self.contextFactory = CoreDataContextFactory(persistence: persistence)
        self.transactionExecutor = CoreDataTransactionExecutor(contextFactory: contextFactory)
        self.animalWriteBoundary = CoreDataAnimalWriteBoundary()
        self.animalAggregateWriteGate = CoreDataAsyncSerialGate()
        self.fieldCheckWriteGate = CoreDataAsyncSerialGate()
        self.workingWriteGate = CoreDataAsyncSerialGate()
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
