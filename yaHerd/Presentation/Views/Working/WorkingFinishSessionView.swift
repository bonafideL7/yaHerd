import SwiftUI

struct WorkingFinishSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(AppNavigationState.self) private var navigation
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    private var repository: any WorkingFinishSessionRepository {
        workingDependencies.finishSessionRepository
    }

    private var pastureRepository: any PastureReferenceDataReader {
        workingDependencies.pastureReferenceReader
    }

    private var animalSummaryReader: any AnimalSummaryReading {
        workingDependencies.animalSummaryReader
    }

    @StateObject private var viewModel: WorkingFinishSessionViewModel
    @State private var animalSummariesByID: [UUID: AnimalSummary] = [:]
    @State private var exceptionAnimalIDs: Set<UUID> = []
    @State private var exceptionDestinationIDs: [UUID: UUID] = [:]
    @State private var showingQueryFilters = false
    @State private var showingExceptionPicker = false
    @State private var showingUnfinishedConfirmation = false
    @State private var errorMessage: String?
    @State private var showingError = false

    init(sessionID: UUID) {
        _viewModel = StateObject(
            wrappedValue: WorkingFinishSessionViewModel(
                sessionID: sessionID,
                workingRepository: EmptyWorkingRepository(),
                pastureRepository: EmptyPastureRepository()
            )
        )
    }

    private var query: AnimalQueryState { navigation.animalQuery }

    private var session: WorkingSessionDetailSnapshot? {
        viewModel.session
    }

    private var orderedItems: [WorkingQueueItemSnapshot] {
        (session?.queueItems ?? []).sorted(by: animalSortOrder)
    }

    private var unfinishedItems: [WorkingQueueItemSnapshot] {
        orderedItems.filter { $0.status != .done }
    }

    private var visibleUnfinishedItems: [WorkingQueueItemSnapshot] {
        WorkingQueueAnimalQueryEngine.apply(
            to: unfinishedItems,
            summariesByID: animalSummariesByID,
            query: query.query,
            formatTag: tagColorLibrary.formattedTag(tagNumber:colorID:)
        )
    }

    private var selectedExceptionItems: [WorkingQueueItemSnapshot] {
        orderedItems.filter { exceptionAnimalIDs.contains($0.id) }
    }

    private var otherPastures: [PastureOption] {
        viewModel.pastures.filter { $0.id != session?.sourcePastureID }
    }

    private var canFinish: Bool {
        guard dataAccessMode.allowsDataMutations,
              session?.status == .active,
              session?.sourcePastureID != nil else {
            return false
        }

        return exceptionAnimalIDs.allSatisfy {
            exceptionDestinationIDs[$0] != nil
        }
    }

    private var finishStatusText: String? {
        guard let session else { return "Loading session…" }
        guard session.status == .active else {
            return "This session is already completed."
        }
        guard session.sourcePastureID != nil else {
            return "A source pasture is required before finishing."
        }

        let missingDestinations = exceptionAnimalIDs.filter {
            exceptionDestinationIDs[$0] == nil
        }.count
        if missingDestinations > 0 {
            return missingDestinations == 1
                ? "Choose a destination for 1 exception."
                : "Choose destinations for \(missingDestinations) exceptions."
        }
        return nil
    }

    var body: some View {
        @Bindable var query = query

        NavigationStack {
            Form {
                summarySection
                querySection
                defaultDestinationSection
                exceptionSection

                if !unfinishedItems.isEmpty {
                    unfinishedSection
                }
            }
            .navigationTitle("Finish Session")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query.searchText, prompt: "Search session animals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                }
            }
            .task {
                viewModel.configure(
                    workingRepository: repository,
                    pastureRepository: pastureRepository
                )
                viewModel.load()
                loadAnimalSummaries()
                seedExceptions()
            }
            .onChange(of: viewModel.session?.id) { _, _ in
                seedExceptions(force: true)
            }
            .onChange(of: exceptionAnimalIDs) { _, _ in
                synchronizeExceptionDestinations()
            }
            .sheet(isPresented: $showingQueryFilters) {
                AnimalFilterView(
                    filter: $query.filter,
                    showRemovedStatuses: $query.showRemovedStatuses,
                    showArchivedRecords: $query.showArchivedRecords,
                    pastureOptions: viewModel.pastures
                )
            }
            .sheet(isPresented: $showingExceptionPicker) {
                WorkingFinishExceptionSelectionView(
                    items: orderedItems,
                    summariesByID: animalSummariesByID,
                    pastureOptions: viewModel.pastures,
                    selection: $exceptionAnimalIDs
                )
            }
            .confirmationDialog(
                "Finish With Unworked Animals?",
                isPresented: $showingUnfinishedConfirmation,
                titleVisibility: .visible
            ) {
                Button("Finish Anyway") {
                    completeSession()
                }
                .disabledWhenDataReadOnly()
                Button("Keep Working", role: .cancel) {}
            } message: {
                Text(unfinishedConfirmationMessage)
            }
            .safeAreaInset(edge: .bottom) {
                WorkingFinishSessionActionBar(
                    isEnabled: canFinish,
                    statusText: finishStatusText,
                    onFinish: finishTapped
                )
            }
            .alert("Can’t Finish Session", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? viewModel.errorMessage ?? "Unknown error")
            }
        }
    }

    private var querySection: some View {
        Section {
            queryControls
        } header: {
            Text("Animal View")
        } footer: {
            Text("Search, filters, and sorting change only the animal rows shown here. Session totals and finish assignments still include every animal.")
        }
    }

    private var queryControls: some View {
        @Bindable var query = query

        return AnimalListInlineTabAccessoryControls(
            sortOrder: $query.sortOrder,
            filtersAreActive: query.filtersAreActive,
            activeFilterCount: query.activeFilterCount,
            hasAnyActiveCriteria: query.hasAnyActiveCriteria,
            onShowFilters: { showingQueryFilters = true },
            onClearAllCriteria: { query.clearCriteria() }
        )
    }

    private var summarySection: some View {
        Section {
            if let session {
                HStack {
                    LabeledContent("Worked") {
                        Text("\(session.doneCount) / \(session.queueItems.count)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }

                LabeledContent("Not Worked") {
                    Text("\(unfinishedItems.count)")
                        .foregroundStyle(unfinishedItems.isEmpty ? Color.secondary : Color.orange)
                        .monospacedDigit()
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        } header: {
            Text("Session Summary")
        }
    }

    private var defaultDestinationSection: some View {
        Section {
            LabeledContent("Return All Animals To") {
                Text(session?.sourcePastureName ?? "Source Pasture")
                    .fontWeight(.semibold)
            }
        } header: {
            Text("Default Return")
        } footer: {
            Text("Every animal returns to the source pasture unless it is selected as an exception below.")
        }
    }

    private var exceptionSection: some View {
        Section {
            Button {
                showingExceptionPicker = true
            } label: {
                HStack {
                    Label("Choose Animals Moving Elsewhere", systemImage: "arrow.triangle.branch")
                    Spacer()
                    Text("\(exceptionAnimalIDs.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .disabled(orderedItems.isEmpty || otherPastures.isEmpty)

            if selectedExceptionItems.isEmpty {
                Text(
                    otherPastures.isEmpty
                        ? "No other pastures are available."
                        : "No destination exceptions."
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(selectedExceptionItems) { item in
                    WorkingFinishDestinationRow(
                        item: item,
                        pastures: otherPastures,
                        destinationID: destinationBinding(for: item.id)
                    )
                }
            }
        } header: {
            Text("Destination Exceptions")
        } footer: {
            if !selectedExceptionItems.isEmpty {
                Text("Only animals listed here will move somewhere other than the source pasture.")
            }
        }
    }

    private var unfinishedSection: some View {
        Section {
            if visibleUnfinishedItems.isEmpty {
                Text("No unworked animals match the current search and filters.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleUnfinishedItems) { item in
                    WorkingFinishAnimalStatusRow(item: item)
                }
            }
        } header: {
            Text("Not Worked")
        } footer: {
            Text("These animals will remain recorded as Not Worked in the completed session.")
        }
    }

    private var unfinishedConfirmationMessage: String {
        let count = unfinishedItems.count
        let noun = count == 1 ? "animal is" : "animals are"
        return "\(count) \(noun) still not worked. They will remain marked Not Worked in the completed session. You can reopen the session later to make corrections."
    }

    private func finishTapped() {
        guard canFinish else { return }
        if unfinishedItems.isEmpty {
            completeSession()
        } else {
            showingUnfinishedConfirmation = true
        }
    }

    private func seedExceptions(force: Bool = false) {
        guard let session else { return }
        if !force && !exceptionAnimalIDs.isEmpty { return }

        let existingExceptions = session.queueItems.filter { item in
            guard let destinationID = item.destinationPastureID else { return false }
            return destinationID != session.sourcePastureID
        }

        exceptionAnimalIDs = Set(existingExceptions.map(\.id))
        exceptionDestinationIDs = Dictionary(
            uniqueKeysWithValues: existingExceptions.compactMap { item in
                guard let destinationID = item.destinationPastureID else { return nil }
                return (item.id, destinationID)
            }
        )
    }

    private func synchronizeExceptionDestinations() {
        exceptionDestinationIDs = exceptionDestinationIDs.filter {
            exceptionAnimalIDs.contains($0.key)
        }

        for item in selectedExceptionItems
            where exceptionDestinationIDs[item.id] == nil
        {
            if let existingDestination = item.destinationPastureID,
               existingDestination != session?.sourcePastureID {
                exceptionDestinationIDs[item.id] = existingDestination
            }
        }
    }

    private func destinationBinding(for itemID: UUID) -> Binding<UUID?> {
        Binding(
            get: { exceptionDestinationIDs[itemID] },
            set: { exceptionDestinationIDs[itemID] = $0 }
        )
    }

    private func completeSession() {
        guard let session,
              let sourcePastureID = session.sourcePastureID else {
            return
        }

        let assignments = orderedItems.map { item in
            WorkingQueueDestinationAssignment(
                queueItemID: item.id,
                destinationPastureID: exceptionAnimalIDs.contains(item.id)
                    ? (exceptionDestinationIDs[item.id] ?? sourcePastureID)
                    : sourcePastureID
            )
        }

        do {
            try CompleteWorkingSessionUseCase(repository: repository).execute(
                sessionID: session.id,
                assignments: assignments
            )
            dismiss()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }

    private func loadAnimalSummaries() {
        do {
            let animals = try animalSummaryReader.fetchAnimals()
            animalSummariesByID = Dictionary(uniqueKeysWithValues: animals.map { ($0.id, $0) })
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }

    private func animalSortOrder(
        _ left: WorkingQueueItemSnapshot,
        _ right: WorkingQueueItemSnapshot
    ) -> Bool {
        let leftTag = left.animalDisplayTagNumber ?? ""
        let rightTag = right.animalDisplayTagNumber ?? ""
        let comparison = leftTag.localizedStandardCompare(rightTag)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return left.id.uuidString < right.id.uuidString
    }
}

private struct WorkingFinishSessionActionBar: View {
    let isEnabled: Bool
    let statusText: String?
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let statusText {
                Text(statusText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: onFinish) {
                Label("Finish Session", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!isEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }
}

private struct WorkingFinishExceptionSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigationState.self) private var navigation
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    let items: [WorkingQueueItemSnapshot]
    let summariesByID: [UUID: AnimalSummary]
    let pastureOptions: [PastureOption]
    @Binding var selection: Set<UUID>
    @State private var showingQueryFilters = false

    private var query: AnimalQueryState { navigation.animalQuery }

    private var filteredItems: [WorkingQueueItemSnapshot] {
        WorkingQueueAnimalQueryEngine.apply(
            to: items,
            summariesByID: summariesByID,
            query: query.query,
            formatTag: tagColorLibrary.formattedTag(tagNumber:colorID:)
        )
    }

    var body: some View {
        @Bindable var query = query

        NavigationStack {
            List(selection: $selection) {
                ForEach(filteredItems) { item in
                    WorkingFinishAnimalStatusRow(item: item)
                        .tag(item.id)
                }
            }
            .overlay {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        query.hasAnyActiveCriteria ? "No Matching Animals" : "No Animals",
                        systemImage: query.hasAnyActiveCriteria ? "magnifyingglass" : "tag",
                        description: Text(
                            query.hasAnyActiveCriteria
                                ? "No session animals match the current search and filters."
                                : "This session does not contain any animals."
                        )
                    )
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Destination Exceptions")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query.searchText, prompt: "Search tag, color, or name")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                queryControls
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        selection.removeAll()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingQueryFilters) {
                AnimalFilterView(
                    filter: $query.filter,
                    showRemovedStatuses: $query.showRemovedStatuses,
                    showArchivedRecords: $query.showArchivedRecords,
                    pastureOptions: pastureOptions
                )
            }
        }
    }

    private var queryControls: some View {
        @Bindable var query = query

        return AnimalListAdaptiveTabAccessoryControls(
            sortOrder: $query.sortOrder,
            filtersAreActive: query.filtersAreActive,
            activeFilterCount: query.activeFilterCount,
            hasAnyActiveCriteria: query.hasAnyActiveCriteria,
            onShowFilters: { showingQueryFilters = true },
            onClearAllCriteria: { query.clearCriteria() }
        )
    }
}

private struct WorkingFinishDestinationRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    let item: WorkingQueueItemSnapshot
    let pastures: [PastureOption]
    @Binding var destinationID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WorkingFinishAnimalStatusRow(item: item)

            Picker("Destination", selection: $destinationID) {
                Text("Choose Pasture").tag(Optional<UUID>.none)
                ForEach(pastures) { pasture in
                    Text(pasture.name).tag(Optional(pasture.id))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WorkingFinishAnimalStatusRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    let item: WorkingQueueItemSnapshot

    var body: some View {
        HStack(spacing: 12) {
            if let tagNumber = item.animalDisplayTagNumber {
                let tagDefinition = tagColorLibrary.resolvedDefinition(
                    tagColorID: item.animalDisplayTagColorID
                )
                let damTagDefinition = tagColorLibrary.resolvedDefinition(
                    tagColorID: item.animalDamDisplayTagColorID
                )

                AnimalTagView(
                    tagNumber: tagNumber,
                    color: tagDefinition.color,
                    colorName: tagDefinition.name,
                    size: .compact,
                    damTagNumber: item.animalDamDisplayTagNumber,
                    damTagColor: damTagDefinition.color,
                    damTagColorName: damTagDefinition.name
                )
            } else {
                Text("Missing Animal")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(item.status == .done ? "Worked" : "Not Worked")
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.status == .done ? Color.secondary : Color.orange)
        }
    }
}
