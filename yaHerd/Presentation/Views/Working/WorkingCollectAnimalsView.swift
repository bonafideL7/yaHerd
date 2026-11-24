//
//  WorkingCollectAnimalsView.swift
//  yaHerd
//

import SwiftUI

struct WorkingCollectAnimalsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    private var repository: any WorkingCollectAnimalsRepository { workingDependencies.collectAnimalsRepository }
    private var animalReferenceQueryReader: (any AnimalReferenceQueryReading)? {
        workingDependencies.animalReferenceQueryReader
    }
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Environment(AppCurrentHerdSelection.self) private var herdSelection

    let sessionID: UUID

    @State private var session: WorkingSessionDetailSnapshot?
    @State private var availableAnimals: [AnimalSummary] = []
    @State private var selectedAnimalIDs: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var searchText: String = ""
    @State private var isCollecting = false
    @State private var collectionTask: Task<Void, Never>?
    @State private var isLoading = true
    @State private var loadErrorMessage: String?
    @State private var loadToken = UUID()
    @State private var alertTitle = "Can’t Save"

    private var eligibleAnimals: [AnimalSummary] {
        guard let session, session.isSourcePastureAvailable else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingAnimalIDs = Set(session.queueItems.compactMap(\.animalID))
        return WorkingCollectAnimalsEligibility.candidates(
            from: availableAnimals,
            sourcePastureID: session.sourcePastureID,
            existingAnimalIDs: existingAnimalIDs
        )
            .filter { animal in
                guard !query.isEmpty else { return true }
                return animal.displayTagNumber.localizedCaseInsensitiveContains(query)
                    || tagColorLibrary.formattedTag(tagNumber: animal.displayTagNumber, colorID: animal.displayTagColorID)
                        .localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                lhs.displayTagNumber.localizedStandardCompare(rhs.displayTagNumber) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selectedAnimalIDs) {
                ForEach(eligibleAnimals) { animal in
                    HStack(spacing: 12) {
                        let def = tagColorLibrary.resolvedDefinition(tagColorID: animal.displayTagColorID)
                        let damDef = tagColorLibrary.resolvedDefinition(tagColorID: animal.damDisplayTagColorID)
                        VStack(alignment: .leading, spacing: 6) {
                            AnimalTagView(
                                tagNumber: animal.displayTagNumber,
                                color: def.color,
                                colorName: def.name,
                                damTagNumber: animal.damDisplayTagNumber,
                                damTagColor: damDef.color,
                                damTagColorName: damDef.name,
                                damTagVisibility: animal.animalType == .calf ? .always : .whenUntagged
                            )
                            Text(animal.sex.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .tag(animal.id)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("Loading eligible animals…")
                } else if session == nil {
                    ContentUnavailableView {
                        Label("Unable to Load Session", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadErrorMessage ?? "The session is no longer available.")
                    } actions: {
                        Button("Retry") {
                            Task { @MainActor in await load() }
                        }
                    }
                } else if eligibleAnimals.isEmpty {
                    ContentUnavailableView {
                        Label("No Eligible Animals", systemImage: "list.bullet")
                    } description: {
                        Text(
                            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "No active animals are available to collect from this session’s source pasture."
                                : "No animals match the search."
                        )
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Collect")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isCollecting)
            .searchable(text: $searchText, prompt: "Search tag")
            .task(id: workingDependencies.mutationStream.workingSessionRevision) {
                await load(preserveSelection: true)
            }
            .onDisappear { collectionTask?.cancel() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { @MainActor in await load() }
                    } label: {
                        Label("Refresh Eligible Animals", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading || isCollecting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        collectSelected()
                    }
                    .disabled(
                        isCollecting
                            || isLoading
                            || selectedAnimalIDs.isEmpty
                            || !selectedAnimalIDs.isSubset(of: Set(availableAnimals.map(\.id)))
                            || session?.isSourcePastureAvailable != true
                    )
                    .disabledWhenDataReadOnly()
                }
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                        .disabled(isCollecting)
                }
            }
            .alert(alertTitle, isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @MainActor
    private func load(preserveSelection: Bool = false) async {
        guard !isCollecting else { return }
        let priorSelection = preserveSelection ? selectedAnimalIDs : []
        let token = UUID()
        loadToken = token
        isLoading = true
        session = nil
        availableAnimals = []
        selectedAnimalIDs = []
        loadErrorMessage = nil
        errorMessage = nil
        showingError = false

        do {
            guard let loadedSession = try repository.fetchSessionDetail(id: sessionID) else {
                throw WorkingCollectCandidateError.missingSession
            }
            let candidates: [AnimalSummary]
            if loadedSession.isSourcePastureAvailable, loadedSession.sourcePastureID != nil {
                guard let animalReferenceQueryReader else {
                    throw WorkingCollectCandidateError.queryUnavailable
                }
                candidates = try await WorkingCollectAnimalsEligibility.loadCandidates(
                    for: loadedSession,
                    using: animalReferenceQueryReader
                )
            } else {
                candidates = []
            }
            try Task.checkCancellation()
            guard token == loadToken else { return }
            session = loadedSession
            availableAnimals = candidates
            selectedAnimalIDs = priorSelection.intersection(Set(candidates.map(\.id)))
            isLoading = false
        } catch is CancellationError {
            if token == loadToken {
                isLoading = false
            }
        } catch {
            guard token == loadToken else { return }
            isLoading = false
            loadErrorMessage = UserVisibleErrorMessage.make(error)
            errorMessage = loadErrorMessage
            alertTitle = "Can’t Load"
            showingError = true
        }
    }

    private func collectSelected() {
        guard !isCollecting,
              !isLoading,
              !selectedAnimalIDs.isEmpty,
              selectedAnimalIDs.isSubset(of: Set(availableAnimals.map(\.id))),
              session?.isSourcePastureAvailable == true else {
            return
        }

        guard let originatingHerdID = herdSelection.currentHerdID else { return }
        let animalIDs = Array(selectedAnimalIDs)
        let sourcePastureID = session?.sourcePastureID
        isCollecting = true
        collectionTask = Task { @MainActor in
            defer {
                isCollecting = false
                collectionTask = nil
            }

            do {
                let completed = try await WorkingCollectAnimalsMoveAction.execute(
                    sessionID: sessionID,
                    animalIDs: animalIDs,
                    sourcePastureID: sourcePastureID,
                    originatingHerdID: originatingHerdID,
                    currentHerdSelection: herdSelection,
                    repository: repository
                )
                guard completed else { return }
                dismiss()
            } catch {
                guard !Task.isCancelled,
                      herdSelection.currentHerdID == originatingHerdID else { return }
                errorMessage = UserVisibleErrorMessage.make(error)
                alertTitle = "Can’t Save"
                showingError = true
            }
        }
    }
}

/// Binds a deferred collection request to the Herd that owned the visible
/// selection when Move was tapped. The repository still owns transaction routing.
@MainActor
enum WorkingCollectAnimalsMoveAction {
    static func execute(
        sessionID: UUID,
        animalIDs: [UUID],
        sourcePastureID: UUID?,
        originatingHerdID: UUID,
        currentHerdSelection: any CurrentHerdSelectionReading,
        repository: any WorkingCollectAnimalsRepository
    ) async throws -> Bool {
        guard !Task.isCancelled,
              currentHerdSelection.currentHerdID == originatingHerdID else {
            return false
        }

        // The session or roster can change while the picker is open.
        guard let current = try repository.fetchSessionDetail(id: sessionID),
              current.isSourcePastureAvailable,
              current.sourcePastureID == sourcePastureID,
              Set(animalIDs).isDisjoint(
                with: Set(current.queueItems.compactMap(\.animalID))
              ) else {
            throw WorkingCollectCandidateError.staleSession
        }

        try Task.checkCancellation()
        guard currentHerdSelection.currentHerdID == originatingHerdID else {
            return false
        }
        try await repository.collectAnimals(
            sessionID: sessionID,
            animalIDs: animalIDs
        )
        return !Task.isCancelled
            && currentHerdSelection.currentHerdID == originatingHerdID
    }
}

enum WorkingCollectAnimalsEligibility {
    /// The M9 read service owns Herd, activity, archive, and location filters.
    /// Hold pages off-screen until all pages succeed, so Move cannot act on
    /// a partial list after a transient store read failure.
    @MainActor
    static func loadCandidates(
        for session: WorkingSessionDetailSnapshot,
        using reader: any AnimalReferenceQueryReading
    ) async throws -> [AnimalSummary] {
        guard session.isSourcePastureAvailable,
              let sourcePastureID = session.sourcePastureID else { return [] }

        let excludedIDs = Set(session.queueItems.compactMap(\.animalID))
        let query = AnimalReferenceQuery(
            pastureScope: .pasture(sourcePastureID),
            location: .pasture,
            excludedAnimalIDs: Array(excludedIDs),
            sortOrder: .displayTag
        )
        // One reference cohort from one pinned Core Data query generation:
        // independent offset pages can skip/duplicate eligible Animals if
        // another transaction changes the roster between requests.
        let animals = try await reader.fetchAnimalReferenceSnapshot(
            matching: query
        )
        try Task.checkCancellation()
        return candidates(
            from: animals,
            sourcePastureID: sourcePastureID,
            existingAnimalIDs: excludedIDs
        )
    }

    static func candidates(
        from animals: [AnimalSummary],
        sourcePastureID: UUID?,
        existingAnimalIDs: Set<UUID>
    ) -> [AnimalSummary] {
        guard let sourcePastureID else { return [] }

        return animals.filter { animal in
            animal.status == .active
                && !animal.isArchived
                && animal.pastureID == sourcePastureID
                && animal.location == .pasture
                && !existingAnimalIDs.contains(animal.id)
        }
    }
}

private enum WorkingCollectCandidateError: LocalizedError {
    case missingSession
    case queryUnavailable
    case staleSession

    var errorDescription: String? {
        switch self {
        case .missingSession:
            "The Working session could not be found. Close this picker and reopen the session."
        case .queryUnavailable:
            "The Core Data animal lookup is unavailable. Close the picker and retry."
        case .staleSession:
            "The Working session changed while this picker was open. Refresh the session and choose the animals again."
        }
    }
}
