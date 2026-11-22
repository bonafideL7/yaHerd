import Foundation
import Observation

struct FieldCheckSessionCountProjection: Equatable, Sendable {
    let totalSeen: Int
    let remainingExpectedCount: Int
    let countVariance: Int

    var requiresFinishConfirmation: Bool {
        remainingExpectedCount > 0 || countVariance != 0
    }
}

@MainActor
@Observable
final class FieldCheckSessionDetailViewModel {
    private(set) var detail: FieldCheckSessionDetailSnapshot?
    private(set) var quickAnimalTypeCountsDraft: [AnimalType: Int] = [:]
    private(set) var notesDraft = ""
    private(set) var isCompletingSession = false
    var errorMessage: String?
    var hasLoaded = false

    @ObservationIgnored private var mutationObservationTask: Task<Void, Never>?
    @ObservationIgnored private var quickCountMutationTask: Task<Bool, Never>?
    @ObservationIgnored private var pendingQuickAnimalTypeCounts: [AnimalType: Int]?
    @ObservationIgnored private var orderedMutationTail: Task<Bool, Never>?
    @ObservationIgnored private var orderedMutationSequence: UInt64 = 0
    @ObservationIgnored private var observedSessionID: UUID?
    private var lastLoadedRevision: UInt64 = 0

    func observe(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository,
        mutationStream: any ApplicationMutationStreaming,
        didLoad: @escaping @MainActor () -> Void = {},
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        guard mayContinue() else { return }
        startObservingIfNeeded(
            sessionID: sessionID,
            using: repository,
            mutationStream: mutationStream,
            didLoad: didLoad,
            mayContinue: mayContinue
        )
        _ = load(sessionID: sessionID, using: repository, mayContinue: mayContinue)
        await mutationObservationTask?.value
    }

    @discardableResult
    func load(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) -> Bool {
        guard mayContinue() else { return false }
        startObservingIfNeeded(sessionID: sessionID, using: repository, mayContinue: mayContinue)
        defer { hasLoaded = true }

        do {
            let loadedDetail = try repository.fetchSessionDetail(id: sessionID)
            guard mayContinue() else { return false }
            detail = loadedDetail
            notesDraft = loadedDetail?.notes ?? ""
            syncQuickCountDraftFromLoadedDetailIfIdle()
            errorMessage = nil
            markCurrentRevision(using: repository)
            return true
        } catch {
            guard mayContinue() else { return false }
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }

    @discardableResult
    func refresh(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) -> Bool {
        guard mayContinue() else { return false }
        startObservingIfNeeded(sessionID: sessionID, using: repository, mayContinue: mayContinue)

        do {
            let previousDetail = detail
            let loadedDetail = try repository.fetchSessionDetail(id: sessionID)
            guard mayContinue() else { return false }
            if let loadedDetail {
                notesDraft = DraftRefreshPolicy.reconciledValue(
                    draft: notesDraft,
                    previouslyLoadedValue: previousDetail?.notes,
                    refreshedValue: loadedDetail.notes,
                    isSameRecord: previousDetail?.id == loadedDetail.id,
                    normalize: { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                )
            }
            detail = loadedDetail
            syncQuickCountDraftFromLoadedDetailIfIdle()
            errorMessage = nil
            return true
        } catch {
            guard mayContinue() else { return false }
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }

    func invalidateForHerdChange() {
        mutationObservationTask?.cancel()
        mutationObservationTask = nil
        observedSessionID = nil
        lastLoadedRevision = 0
        detail = nil
        quickAnimalTypeCountsDraft = [:]
        notesDraft = ""
        errorMessage = nil
        hasLoaded = false
    }

    func countProjection(
        for detail: FieldCheckSessionDetailSnapshot
    ) -> FieldCheckSessionCountProjection {
        let totalSeen = FieldCheckQuickCountRules.totalSeen(
            quickCounts: quickAnimalTypeCountsDraft,
            rosterEntries: detail.animalChecks.map(\.quickCountRosterEntry)
        )

        return FieldCheckSessionCountProjection(
            totalSeen: totalSeen,
            remainingExpectedCount: max(detail.expectedHeadCountSnapshot - totalSeen, 0),
            countVariance: totalSeen - detail.expectedHeadCountSnapshot
        )
    }

    private func performOrderedMutation(
        allowsDuringCompletion: Bool = false,
        mayContinue: @escaping @MainActor () -> Bool = { true },
        _ operation: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        guard (allowsDuringCompletion || !isCompletingSession),
              mayContinue() else {
            return false
        }

        let predecessor = orderedMutationTail
        let quickCountPrerequisite = quickCountMutationTask
        orderedMutationSequence &+= 1
        let sequence = orderedMutationSequence

        let task = Task { @MainActor in
            if let predecessor,
               !(await predecessor.value) {
                return false
            }

            if let quickCountPrerequisite,
               !(await quickCountPrerequisite.value) {
                return false
            }

            // Selection may change while an earlier write is suspended.
            guard !Task.isCancelled, mayContinue() else { return false }
            return await operation()
        }

        orderedMutationTail = task
        let result = await task.value

        if orderedMutationSequence == sequence {
            orderedMutationTail = nil
        }

        return result
    }

    func updateNotesDraft(_ notes: String) {
        guard !isCompletingSession,
              detail?.isCompleted == false else {
            return
        }
        notesDraft = notes
    }

    @discardableResult
    func beginSessionCompletion() -> Bool {
        guard !isCompletingSession,
              detail?.isCompleted == false else {
            return false
        }
        isCompletingSession = true
        return true
    }

    private func endSessionCompletion() {
        isCompletingSession = false
    }

    private func persistNotesOperation(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async -> Bool {
        guard mayContinue() else { return false }
        guard let detail else {
            return true
        }

        let normalizedDraft = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSaved = detail.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedDraft != normalizedSaved else {
            return true
        }

        do {
            try await repository.updateNotes(sessionID: sessionID, notes: notesDraft)
            guard mayContinue() else { return false }
            refresh(sessionID: sessionID, using: repository)
            return true
        } catch {
            guard mayContinue() else { return false }
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }

    @discardableResult
    func persistNotes(
        sessionID: UUID,
        originatingHerdID: UUID,
        originatingSelectionRevision: UInt64,
        currentHerdSelection: any CurrentHerdSelectionReading,
        using repository: any FieldCheckSessionDetailRepository
    ) async -> Bool {
        let selectionIsUnchanged: @MainActor () -> Bool = {
            currentHerdSelection.currentHerdID == originatingHerdID
                && currentHerdSelection.selectionRevision == originatingSelectionRevision
        }
        guard selectionIsUnchanged() else {
            return false
        }

        return await performOrderedMutation(mayContinue: selectionIsUnchanged) {
            await self.persistNotesOperation(
                sessionID: sessionID,
                using: repository,
                mayContinue: selectionIsUnchanged
            )
        }
    }

    func updateQuickAnimalTypeCounts(
        sessionID: UUID,
        counts: [AnimalType: Int],
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) {
        guard !isCompletingSession,
              detail?.isCompleted == false,
              mayContinue() else {
            return
        }

        quickAnimalTypeCountsDraft = counts
        pendingQuickAnimalTypeCounts = counts

        guard quickCountMutationTask == nil else {
            return
        }

        quickCountMutationTask = Task { @MainActor in
            await drainQuickAnimalTypeCountUpdates(
                sessionID: sessionID,
                using: repository,
                mayContinue: mayContinue
            )
        }
    }

    private func drainQuickAnimalTypeCountUpdates(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool
    ) async -> Bool {
        do {
            while let counts = pendingQuickAnimalTypeCounts {
                // The repository resolves the selected Herd per write. An old
                // queue must not send another mutation after selection changes.
                guard !Task.isCancelled, mayContinue() else {
                    pendingQuickAnimalTypeCounts = nil
                    quickCountMutationTask = nil
                    return false
                }
                pendingQuickAnimalTypeCounts = nil
                try await repository.updateQuickAnimalTypeCounts(
                    sessionID: sessionID,
                    counts: counts
                )
            }

            let canPublish = !Task.isCancelled && mayContinue()
            quickCountMutationTask = nil
            guard canPublish else {
                pendingQuickAnimalTypeCounts = nil
                return false
            }
            _ = refresh(sessionID: sessionID, using: repository)
            return true
        } catch {
            pendingQuickAnimalTypeCounts = nil
            quickCountMutationTask = nil
            // An old session cannot overwrite the new Herd's error state.
            guard !Task.isCancelled, mayContinue() else { return false }
            let message = UserVisibleErrorMessage.make(error)
            _ = refresh(sessionID: sessionID, using: repository)
            errorMessage = message
            return false
        }
    }

    private func syncQuickCountDraftFromLoadedDetailIfIdle() {
        guard quickCountMutationTask == nil,
              pendingQuickAnimalTypeCounts == nil else {
            return
        }
        quickAnimalTypeCountsDraft = detail?.quickAnimalTypeCounts ?? [:]
    }

    func setAnimalCheckCounted(
        sessionID: UUID,
        animalCheckID: UUID,
        isCounted: Bool,
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await repository.setAnimalCheckCounted(
                    sessionID: sessionID,
                    animalCheckID: animalCheckID,
                    isCounted: isCounted
                )
                guard mayContinue() else { return false }
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func setAnimalCheckMissing(
        sessionID: UUID,
        animalCheckID: UUID,
        isMissing: Bool,
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await repository.setAnimalCheckMissing(
                    sessionID: sessionID,
                    animalCheckID: animalCheckID,
                    isMissing: isMissing
                )
                guard mayContinue() else { return false }
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func addTrackedAnimalToSession(
        sessionID: UUID,
        animalID: UUID,
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async -> Bool {
        await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await repository.addTrackedAnimalToSession(
                    sessionID: sessionID,
                    animalID: animalID,
                    checkedAt: .now
                )
                guard mayContinue() else { return false }
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func addFinding(
        sessionID: UUID,
        input: FieldCheckFindingInput,
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await repository.addFinding(sessionID: sessionID, input: input)
                guard mayContinue() else { return false }
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func updateFinding(
        sessionID: UUID,
        findingID: UUID,
        input: FieldCheckFindingInput,
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await repository.updateFinding(
                    sessionID: sessionID,
                    findingID: findingID,
                    input: input
                )
                guard mayContinue() else { return false }
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func updateFindingStatus(
        sessionID: UUID,
        findingID: UUID,
        status: FieldCheckFindingStatus,
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await repository.updateFindingStatus(
                    sessionID: sessionID,
                    findingID: findingID,
                    status: status
                )
                guard mayContinue() else { return false }
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func deleteFinding(
        sessionID: UUID,
        findingID: UUID,
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await repository.deleteFinding(
                    sessionID: sessionID,
                    findingID: findingID
                )
                guard mayContinue() else { return false }
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func completeSession(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository,
        completionAlreadyAccepted: Bool = false,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        if completionAlreadyAccepted {
            guard isCompletingSession else {
                return
            }
        } else {
            guard beginSessionCompletion() else {
                return
            }
        }

        defer { endSessionCompletion() }
        guard mayContinue() else { return }

        _ = await performOrderedMutation(allowsDuringCompletion: true, mayContinue: mayContinue) {
            guard await self.persistNotesOperation(
                sessionID: sessionID,
                using: repository,
                mayContinue: mayContinue
            ) else {
                return false
            }

            guard mayContinue() else { return false }
            do {
                try await repository.completeSession(id: sessionID)
                guard mayContinue() else { return false }
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func reopenSession(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await repository.reopenSession(id: sessionID)
                guard mayContinue() else { return false }
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    private func startObservingIfNeeded(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository,
        mutationStream explicitMutationStream: (any ApplicationMutationStreaming)? = nil,
        didLoad: @escaping @MainActor () -> Void = {},
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) {
        guard mayContinue() else { return }
        if observedSessionID != sessionID {
            mutationObservationTask?.cancel()
            mutationObservationTask = nil
            observedSessionID = sessionID
        }
        guard mutationObservationTask == nil else { return }

        let mutationStream: any ApplicationMutationStreaming
        if let explicitMutationStream {
            mutationStream = explicitMutationStream
        } else if let provider = repository as? any ApplicationMutationStreamProviding {
            mutationStream = provider.applicationMutationStream
        } else {
            return
        }

        mutationObservationTask = Task { @MainActor [weak self] in
            let startingRevision = self?.lastLoadedRevision ?? 0
            for await revision in mutationStream.revisions(
                for: .fieldChecks,
                after: startingRevision
            ) {
                guard !Task.isCancelled, mayContinue(), let self else { return }
                if self.refresh(sessionID: sessionID, using: repository, mayContinue: mayContinue) {
                    self.lastLoadedRevision = revision
                    didLoad()
                }
            }
        }
    }

    private func markCurrentRevision(using repository: any FieldCheckSessionDetailRepository) {
        guard let provider = repository as? any ApplicationMutationStreamProviding else { return }
        lastLoadedRevision = provider.applicationMutationStream.fieldCheckRevision
    }
}


@MainActor
@Observable
final class FieldCheckAnimalDetailViewModel {
    @ObservationIgnored private let dateProvider: any DateProviding
    @ObservationIgnored private var orderedMutationTail: Task<Bool, Never>?
    @ObservationIgnored private var orderedMutationSequence: UInt64 = 0
    private(set) var animalDetail: AnimalDetailSnapshot?
    private(set) var sessionDetail: FieldCheckSessionDetailSnapshot?
    var preparedOffspringEditor: PreparedAnimalEditor?
    var errorMessage: String?
    var hasLoaded = false

    /// A mounted Field Check animal detail may outlive its navigation route.
    /// Its cached records remain private to the selection that opened it.
    func isOriginatingSelectionCurrent(
        _ selection: any CurrentHerdSelectionReading,
        originatingHerdID: UUID?,
        originatingSelectionRevision: UInt64?
    ) -> Bool {
        guard let originatingHerdID, let originatingSelectionRevision else {
            return false
        }
        return selection.currentHerdID == originatingHerdID
            && selection.selectionRevision == originatingSelectionRevision
    }

    var animalCheck: FieldCheckAnimalCheckSnapshot? {
        guard let animalID = animalDetail?.id else { return nil }
        return sessionDetail?.animalChecks.first(where: { $0.animalID == animalID })
    }

    var animalFindings: [FieldCheckFindingSnapshot] {
        guard let animalID = animalDetail?.id else { return [] }
        return (sessionDetail?.findings ?? [])
            .filter { $0.animalID == animalID }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    init(dateProvider: any DateProviding = SystemDateProvider()) {
        self.dateProvider = dateProvider
    }

    func load(
        animalID: UUID,
        sessionID: UUID,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) {
        defer { hasLoaded = true }

        do {
            animalDetail = try animalRepository.fetchAnimalDetail(id: animalID)
            preparedOffspringEditor = try PrepareOffspringDraftUseCase(repository: animalRepository).execute(forDamID: animalID)
            sessionDetail = try fieldCheckRepository.fetchSessionDetail(id: sessionID)
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func refresh(
        animalID: UUID,
        sessionID: UUID,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) {
        do {
            animalDetail = try animalRepository.fetchAnimalDetail(id: animalID)
            preparedOffspringEditor = try PrepareOffspringDraftUseCase(repository: animalRepository).execute(forDamID: animalID)
            sessionDetail = try fieldCheckRepository.fetchSessionDetail(id: sessionID)
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    private func performOrderedMutation(
        mayContinue: @escaping @MainActor () -> Bool = { true },
        _ operation: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        guard !Task.isCancelled, mayContinue() else { return false }
        let predecessor = orderedMutationTail
        orderedMutationSequence &+= 1
        let sequence = orderedMutationSequence

        let task = Task { @MainActor in
            if let predecessor,
               !(await predecessor.value) {
                return false
            }
            guard !Task.isCancelled, mayContinue() else { return false }
            return await operation()
        }

        orderedMutationTail = task
        let result = await task.value

        if orderedMutationSequence == sequence {
            orderedMutationTail = nil
        }

        return result
    }

    func setAnimalCheckCounted(
        animalID: UUID,
        sessionID: UUID,
        isCounted: Bool,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        guard let animalCheckID = animalCheck?.id else { return }

        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await fieldCheckRepository.setAnimalCheckCounted(
                    sessionID: sessionID,
                    animalCheckID: animalCheckID,
                    isCounted: isCounted
                )
                guard mayContinue() else { return false }
                self.refresh(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func setAnimalCheckMissing(
        animalID: UUID,
        sessionID: UUID,
        isMissing: Bool,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        guard let animalCheckID = animalCheck?.id else { return }

        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await fieldCheckRepository.setAnimalCheckMissing(
                    sessionID: sessionID,
                    animalCheckID: animalCheckID,
                    isMissing: isMissing
                )
                guard mayContinue() else { return false }
                self.refresh(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func addTrackedAnimalToSession(
        animalID: UUID,
        sessionID: UUID,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async throws {
        var operationError: Error?
        let succeeded = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await fieldCheckRepository.addTrackedAnimalToSession(
                    sessionID: sessionID,
                    animalID: animalID,
                    checkedAt: self.dateProvider.now
                )
                guard mayContinue() else { return false }
                return true
            } catch {
                guard mayContinue() else { return false }
                operationError = error
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }

        guard succeeded else {
            throw operationError ?? FieldCheckAnimalDetailMutationError.priorMutationFailed
        }
    }

    func addFinding(
        animalID: UUID,
        sessionID: UUID,
        input: FieldCheckFindingInput,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await fieldCheckRepository.addFinding(
                    sessionID: sessionID,
                    input: input
                )
                guard mayContinue() else { return false }
                self.refresh(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func updateFinding(
        animalID: UUID,
        sessionID: UUID,
        findingID: UUID,
        input: FieldCheckFindingInput,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await fieldCheckRepository.updateFinding(
                    sessionID: sessionID,
                    findingID: findingID,
                    input: input
                )
                guard mayContinue() else { return false }
                self.refresh(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func updateFindingStatus(
        animalID: UUID,
        sessionID: UUID,
        findingID: UUID,
        status: FieldCheckFindingStatus,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await fieldCheckRepository.updateFindingStatus(
                    sessionID: sessionID,
                    findingID: findingID,
                    status: status
                )
                guard mayContinue() else { return false }
                self.refresh(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func deleteFinding(
        animalID: UUID,
        sessionID: UUID,
        findingID: UUID,
        animalRepository: any AnimalDetailRepository,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository,
        mayContinue: @escaping @MainActor () -> Bool = { true }
    ) async {
        _ = await performOrderedMutation(mayContinue: mayContinue) {
            do {
                try await fieldCheckRepository.deleteFinding(
                    sessionID: sessionID,
                    findingID: findingID
                )
                guard mayContinue() else { return false }
                self.refresh(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
                return true
            } catch {
                guard mayContinue() else { return false }
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

}

private enum FieldCheckAnimalDetailMutationError: LocalizedError {
    case priorMutationFailed

    var errorDescription: String? {
        "A previous Field Check action failed. Retry after reviewing the current animal state."
    }
}

@MainActor
@Observable
final class FieldCheckTrackedAnimalPickerViewModel {
    private(set) var animals: [AnimalSummary] = []
    private(set) var isSubmittingSelection = false
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var loadErrorMessage: String?
    var searchText = ""
    var errorMessage: String?

    @ObservationIgnored private var loadToken = UUID()
    @ObservationIgnored private var loadedHerdID: UUID?
    @ObservationIgnored private var loadedSelectionRevision: UInt64?

    func hasCurrentCandidates(
        for selection: AppCurrentHerdSelection,
        originatingSelectionRevision: UInt64
    ) -> Bool {
        hasLoaded
            && loadedHerdID != nil
            && loadedHerdID == selection.currentHerdID
            && loadedSelectionRevision == originatingSelectionRevision
            && selection.selectionRevision == originatingSelectionRevision
    }

    /// Read the complete eligible cohort from one pinned Core Data generation.
    /// Do not publish any candidates until that snapshot has succeeded.
    func load(
        for session: FieldCheckSessionDetailSnapshot,
        using reader: (any AnimalReferenceQueryReading)?,
        selection: AppCurrentHerdSelection,
        originatingSelectionRevision: UInt64
    ) async {
        guard !isSubmittingSelection else { return }
        let token = UUID()
        loadToken = token
        animals = []
        isLoading = true
        hasLoaded = false
        loadErrorMessage = nil
        errorMessage = nil
        loadedHerdID = nil
        loadedSelectionRevision = nil

        // An old picker must not start a new query against a different Herd.
        guard let originatingHerdID = selection.currentHerdID,
              selection.selectionRevision == originatingSelectionRevision else {
            isLoading = false
            return
        }

        guard let destinationPastureID = session.pastureID,
              !session.isPastureArchived,
              !session.isCompleted else {
            isLoading = false
            loadErrorMessage = "This Field Check no longer has an active destination pasture."
            errorMessage = loadErrorMessage
            return
        }

        guard let reader else {
            isLoading = false
            loadErrorMessage = "The Field Check Animal reference lookup is not configured."
            errorMessage = loadErrorMessage
            return
        }

        let checkedIDs = Set(session.animalChecks.compactMap(\.animalID))
        let query = AnimalReferenceQuery(
            pastureScope: .notPasture(destinationPastureID),
            location: .any,
            excludedAnimalIDs: Array(checkedIDs),
            sortOrder: .displayTagOrName
        )

        do {
            let snapshot = try await reader.fetchAnimalReferenceSnapshot(matching: query)
            try Task.checkCancellation()
            guard loadToken == token else { return }
            guard selection.currentHerdID == originatingHerdID,
                  selection.selectionRevision == originatingSelectionRevision else {
                isLoading = false
                return
            }

            // Retain the original picker rules as a presentation-level safety
            // boundary, independent of the M9 query's filtering.
            animals = snapshot.filter {
                $0.status == .active
                    && !$0.isArchived
                    && $0.pastureID != destinationPastureID
                    && !checkedIDs.contains($0.id)
            }
            loadedHerdID = originatingHerdID
            loadedSelectionRevision = originatingSelectionRevision
            hasLoaded = true
            isLoading = false
        } catch is CancellationError {
            if loadToken == token {
                isLoading = false
            }
        } catch {
            guard loadToken == token else { return }
            isLoading = false
            guard selection.currentHerdID == originatingHerdID,
                  selection.selectionRevision == originatingSelectionRevision else { return }
            loadErrorMessage = UserVisibleErrorMessage.make(error)
            errorMessage = loadErrorMessage
        }
    }

    func beginSelectionSubmission(
        selection: AppCurrentHerdSelection,
        originatingSelectionRevision: UInt64
    ) -> Bool {
        guard !isSubmittingSelection,
              !isLoading,
              hasCurrentCandidates(
                  for: selection,
                  originatingSelectionRevision: originatingSelectionRevision
              ) else {
            return false
        }
        isSubmittingSelection = true
        return true
    }

    func endSelectionSubmission() {
        isSubmittingSelection = false
    }

    func eligibleAnimals(
        forPastureID pastureID: UUID?,
        excluding checkedAnimalIDs: Set<UUID>
    ) -> [AnimalSummary] {
        guard hasLoaded else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return animals
            .filter { animal in
                animal.status == .active
                    && !animal.isArchived
                    && animal.pastureID != pastureID
                    && !checkedAnimalIDs.contains(animal.id)
            }
            .filter { animal in
                guard !query.isEmpty else { return true }
                return animal.displayTagNumber.localizedCaseInsensitiveContains(query)
                    || animal.name.localizedCaseInsensitiveContains(query)
                    || (animal.pastureName?.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { left, right in
                let lhs = left.displayTagNumber.isEmpty ? left.name : left.displayTagNumber
                let rhs = right.displayTagNumber.isEmpty ? right.name : right.displayTagNumber
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
    }
}
