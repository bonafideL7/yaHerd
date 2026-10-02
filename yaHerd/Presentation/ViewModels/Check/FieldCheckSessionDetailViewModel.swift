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
        didLoad: @escaping @MainActor () -> Void = {}
    ) async {
        startObservingIfNeeded(
            sessionID: sessionID,
            using: repository,
            mutationStream: mutationStream,
            didLoad: didLoad
        )
        _ = load(sessionID: sessionID, using: repository)
        await mutationObservationTask?.value
    }

    @discardableResult
    func load(sessionID: UUID, using repository: any FieldCheckSessionDetailRepository) -> Bool {
        startObservingIfNeeded(sessionID: sessionID, using: repository)
        defer { hasLoaded = true }

        do {
            let loadedDetail = try repository.fetchSessionDetail(id: sessionID)
            detail = loadedDetail
            notesDraft = loadedDetail?.notes ?? ""
            syncQuickCountDraftFromLoadedDetailIfIdle()
            errorMessage = nil
            markCurrentRevision(using: repository)
            return true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }

    @discardableResult
    func refresh(sessionID: UUID, using repository: any FieldCheckSessionDetailRepository) -> Bool {
        startObservingIfNeeded(sessionID: sessionID, using: repository)

        do {
            let previousDetail = detail
            let loadedDetail = try repository.fetchSessionDetail(id: sessionID)
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
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
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
        _ operation: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        guard allowsDuringCompletion || !isCompletingSession else {
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
        using repository: any FieldCheckSessionDetailRepository
    ) async -> Bool {
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
            refresh(sessionID: sessionID, using: repository)
            return true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            return false
        }
    }

    @discardableResult
    func persistNotes(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository
    ) async -> Bool {
        await performOrderedMutation {
            await self.persistNotesOperation(
                sessionID: sessionID,
                using: repository
            )
        }
    }

    func updateQuickAnimalTypeCounts(
        sessionID: UUID,
        counts: [AnimalType: Int],
        using repository: any FieldCheckSessionDetailRepository
    ) {
        guard !isCompletingSession,
              detail?.isCompleted == false else {
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
                using: repository
            )
        }
    }

    private func drainQuickAnimalTypeCountUpdates(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository
    ) async -> Bool {
        do {
            while let counts = pendingQuickAnimalTypeCounts {
                pendingQuickAnimalTypeCounts = nil
                try await repository.updateQuickAnimalTypeCounts(
                    sessionID: sessionID,
                    counts: counts
                )
            }

            quickCountMutationTask = nil
            _ = refresh(sessionID: sessionID, using: repository)
            return true
        } catch {
            pendingQuickAnimalTypeCounts = nil
            quickCountMutationTask = nil
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
        using repository: any FieldCheckSessionDetailRepository
    ) async {
        _ = await performOrderedMutation {
            do {
                try await repository.setAnimalCheckCounted(
                    sessionID: sessionID,
                    animalCheckID: animalCheckID,
                    isCounted: isCounted
                )
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func setAnimalCheckMissing(
        sessionID: UUID,
        animalCheckID: UUID,
        isMissing: Bool,
        using repository: any FieldCheckSessionDetailRepository
    ) async {
        _ = await performOrderedMutation {
            do {
                try await repository.setAnimalCheckMissing(
                    sessionID: sessionID,
                    animalCheckID: animalCheckID,
                    isMissing: isMissing
                )
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func addTrackedAnimalToSession(
        sessionID: UUID,
        animalID: UUID,
        using repository: any FieldCheckSessionDetailRepository
    ) async -> Bool {
        await performOrderedMutation {
            do {
                try await repository.addTrackedAnimalToSession(
                    sessionID: sessionID,
                    animalID: animalID,
                    checkedAt: .now
                )
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func addFinding(
        sessionID: UUID,
        input: FieldCheckFindingInput,
        using repository: any FieldCheckSessionDetailRepository
    ) async {
        _ = await performOrderedMutation {
            do {
                try await repository.addFinding(sessionID: sessionID, input: input)
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func updateFinding(
        sessionID: UUID,
        findingID: UUID,
        input: FieldCheckFindingInput,
        using repository: any FieldCheckSessionDetailRepository
    ) async {
        _ = await performOrderedMutation {
            do {
                try await repository.updateFinding(
                    sessionID: sessionID,
                    findingID: findingID,
                    input: input
                )
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func updateFindingStatus(
        sessionID: UUID,
        findingID: UUID,
        status: FieldCheckFindingStatus,
        using repository: any FieldCheckSessionDetailRepository
    ) async {
        _ = await performOrderedMutation {
            do {
                try await repository.updateFindingStatus(
                    sessionID: sessionID,
                    findingID: findingID,
                    status: status
                )
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func deleteFinding(
        sessionID: UUID,
        findingID: UUID,
        using repository: any FieldCheckSessionDetailRepository
    ) async {
        _ = await performOrderedMutation {
            do {
                try await repository.deleteFinding(
                    sessionID: sessionID,
                    findingID: findingID
                )
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func completeSession(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository,
        completionAlreadyAccepted: Bool = false
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

        _ = await performOrderedMutation(allowsDuringCompletion: true) {
            guard await self.persistNotesOperation(
                sessionID: sessionID,
                using: repository
            ) else {
                return false
            }

            do {
                try await repository.completeSession(id: sessionID)
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func reopenSession(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository
    ) async {
        _ = await performOrderedMutation {
            do {
                try await repository.reopenSession(id: sessionID)
                self.refresh(sessionID: sessionID, using: repository)
                return true
            } catch {
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    private func startObservingIfNeeded(
        sessionID: UUID,
        using repository: any FieldCheckSessionDetailRepository,
        mutationStream explicitMutationStream: (any ApplicationMutationStreaming)? = nil,
        didLoad: @escaping @MainActor () -> Void = {}
    ) {
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
                guard !Task.isCancelled, let self else { return }
                if self.refresh(sessionID: sessionID, using: repository) {
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
        _ operation: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let predecessor = orderedMutationTail
        orderedMutationSequence &+= 1
        let sequence = orderedMutationSequence

        let task = Task { @MainActor in
            if let predecessor,
               !(await predecessor.value) {
                return false
            }
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
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) async {
        guard let animalCheckID = animalCheck?.id else { return }

        _ = await performOrderedMutation {
            do {
                try await fieldCheckRepository.setAnimalCheckCounted(
                    sessionID: sessionID,
                    animalCheckID: animalCheckID,
                    isCounted: isCounted
                )
                self.refresh(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
                return true
            } catch {
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
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) async {
        guard let animalCheckID = animalCheck?.id else { return }

        _ = await performOrderedMutation {
            do {
                try await fieldCheckRepository.setAnimalCheckMissing(
                    sessionID: sessionID,
                    animalCheckID: animalCheckID,
                    isMissing: isMissing
                )
                self.refresh(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
                return true
            } catch {
                self.errorMessage = UserVisibleErrorMessage.make(error)
                return false
            }
        }
    }

    func addTrackedAnimalToSession(
        animalID: UUID,
        sessionID: UUID,
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) async throws {
        var operationError: Error?
        let succeeded = await performOrderedMutation {
            do {
                try await fieldCheckRepository.addTrackedAnimalToSession(
                    sessionID: sessionID,
                    animalID: animalID,
                    checkedAt: self.dateProvider.now
                )
                return true
            } catch {
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
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) async {
        _ = await performOrderedMutation {
            do {
                try await fieldCheckRepository.addFinding(
                    sessionID: sessionID,
                    input: input
                )
                self.refresh(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
                return true
            } catch {
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
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) async {
        _ = await performOrderedMutation {
            do {
                try await fieldCheckRepository.updateFinding(
                    sessionID: sessionID,
                    findingID: findingID,
                    input: input
                )
                self.refresh(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
                return true
            } catch {
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
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) async {
        _ = await performOrderedMutation {
            do {
                try await fieldCheckRepository.updateFindingStatus(
                    sessionID: sessionID,
                    findingID: findingID,
                    status: status
                )
                self.refresh(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
                return true
            } catch {
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
        fieldCheckRepository: any FieldCheckAnimalDetailRepository
    ) async {
        _ = await performOrderedMutation {
            do {
                try await fieldCheckRepository.deleteFinding(
                    sessionID: sessionID,
                    findingID: findingID
                )
                self.refresh(
                    animalID: animalID,
                    sessionID: sessionID,
                    animalRepository: animalRepository,
                    fieldCheckRepository: fieldCheckRepository
                )
                return true
            } catch {
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
    var searchText = ""
    var errorMessage: String?
    var hasLoaded = false

    func load(using repository: any AnimalSummaryReading) {
        defer { hasLoaded = true }

        do {
            animals = try repository.fetchAnimals()
            errorMessage = nil
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
        }
    }

    func beginSelectionSubmission() -> Bool {
        guard !isSubmittingSelection else {
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
