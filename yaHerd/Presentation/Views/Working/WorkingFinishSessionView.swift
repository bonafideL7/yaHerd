import SwiftUI

struct WorkingFinishSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @Environment(AppCurrentHerdSelection.self) private var herdSelection
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    private var repository: any WorkingFinishSessionRepository {
        workingDependencies.finishSessionRepository
    }

    private var pastureRepository: any PastureReferenceDataReader {
        workingDependencies.pastureReferenceReader
    }

    private let originatingHerdID: UUID
    private let originatingSelectionRevision: UInt64

    @StateObject private var viewModel: WorkingFinishSessionViewModel
    @State private var exceptionAnimalIDs: Set<UUID> = []
    @State private var exceptionDestinationIDs: [UUID: UUID] = [:]
    @State private var showingExceptionPicker = false
    @State private var showingUnfinishedConfirmation = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isFinishing = false

    init(sessionID: UUID, originatingHerdID: UUID, originatingSelectionRevision: UInt64) {
        self.originatingHerdID = originatingHerdID
        self.originatingSelectionRevision = originatingSelectionRevision
        _viewModel = StateObject(
            wrappedValue: WorkingFinishSessionViewModel(
                sessionID: sessionID,
                workingRepository: EmptyWorkingRepository(),
                pastureRepository: EmptyPastureRepository()
            )
        )
    }

    private var isViewingOriginatingHerd: Bool {
        herdSelection.currentHerdID == originatingHerdID
            && herdSelection.selectionRevision == originatingSelectionRevision
    }

    private var session: WorkingSessionDetailSnapshot? {
        viewModel.session
    }

    private var orderedItems: [WorkingQueueItemSnapshot] {
        (session?.queueItems ?? []).sorted(by: animalSortOrder)
    }

    private var unfinishedItems: [WorkingQueueItemSnapshot] {
        orderedItems.filter { $0.status != .done }
    }

    private var selectedExceptionItems: [WorkingQueueItemSnapshot] {
        orderedItems.filter { exceptionAnimalIDs.contains($0.id) }
    }

    private var liveSourcePastureID: UUID? {
        guard let session, session.isSourcePastureAvailable else { return nil }
        return session.sourcePastureID
    }

    private var liveSourcePastureName: String? {
        guard let liveSourcePastureID else { return nil }
        return viewModel.pastures.first { $0.id == liveSourcePastureID }?.name
            ?? session?.sourcePastureName
    }

    private var requiresExplicitDestinationForEveryItem: Bool {
        session != nil && liveSourcePastureID == nil
    }

    private var otherPastures: [PastureOption] {
        viewModel.pastures.filter { $0.id != liveSourcePastureID }
    }

    private var canFinish: Bool {
        guard !isFinishing,
              isViewingOriginatingHerd,
              dataAccessMode.allowsDataMutations,
              viewModel.sessionLoadState == .ready,
              viewModel.hasLoadedPastureOptions,
              let session,
              session.status == .active,
              !orderedItems.isEmpty else {
            return false
        }

        if requiresExplicitDestinationForEveryItem {
            return orderedItems.allSatisfy { item in
                exceptionAnimalIDs.contains(item.id)
                    && exceptionDestinationIDs[item.id] != nil
            }
        }

        return exceptionAnimalIDs.allSatisfy {
            exceptionDestinationIDs[$0] != nil
        }
    }

    private var finishStatusText: String? {
        guard isViewingOriginatingHerd else {
            return "The selected Herd changed. Reopen the session to continue."
        }
        guard let session else {
            switch viewModel.sessionLoadState {
            case .loading:
                return "Loading session…"
            case .missing:
                return "This session is not available in the selected Herd. Retry to check again."
            case .failed:
                return "Session details could not be read. Retry before finishing."
            case .ready:
                return "This session is not available."
            }
        }
        guard session.status == .active else {
            return "This session is already completed."
        }
        guard viewModel.hasLoadedPastureOptions else {
            return "Pasture destinations couldn’t be loaded. Retry before finishing."
        }

        if requiresExplicitDestinationForEveryItem {
            let missingDestinations = orderedItems.filter {
                exceptionDestinationIDs[$0.id] == nil
            }.count
            if missingDestinations > 0 {
                return missingDestinations == 1
                    ? "The source pasture is no longer available. Choose a destination for 1 animal."
                    : "The source pasture is no longer available. Choose destinations for \(missingDestinations) animals."
            }
            return nil
        }

        guard liveSourcePastureID != nil else {
            return "A live source pasture is required before finishing."
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
        NavigationStack {
            Form {
                if isViewingOriginatingHerd {
                    switch viewModel.sessionLoadState {
                    case .loading:
                        ProgressView("Loading session…")
                            .frame(maxWidth: .infinity)
                    case .missing, .failed:
                        sessionLoadRecoverySection
                    case .ready:
                        summarySection
                        defaultDestinationSection

                        if viewModel.needsPastureOptionsRetry {
                            pastureLoadRecoverySection
                        }

                        exceptionSection

                        if !unfinishedItems.isEmpty {
                            unfinishedSection
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Working Session Unavailable",
                        systemImage: "arrow.left.arrow.right",
                        description: Text("The selected Herd changed. Reopen the session to continue.")
                    )
                }
            }
            .navigationTitle("Finish Session")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isFinishing)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarCancelButton { dismiss() }
                        .disabled(isFinishing)
                }
            }
            .task {
                guard isViewingOriginatingHerd else { return }
                viewModel.configure(
                    workingRepository: repository,
                    pastureRepository: pastureRepository
                )
                viewModel.load()
                if viewModel.errorMessage != nil &&
                   viewModel.sessionLoadState != .failed {
                    showingError = true
                }
                seedExceptions()
            }
            .onChange(of: viewModel.session?.id) { _, _ in
                guard isViewingOriginatingHerd else { return }
                seedExceptions(force: true)
            }
            .onChange(of: viewModel.hasLoadedPastureOptions) { _, loaded in
                if loaded && isViewingOriginatingHerd {
                    revalidateExceptionDestinationsAgainstLivePastures()
                }
            }
            .onChange(of: exceptionAnimalIDs) { _, _ in
                guard isViewingOriginatingHerd else { return }
                synchronizeExceptionDestinations()
            }
            .onChange(of: herdSelection.selectionRevision) { _, _ in
                guard !isViewingOriginatingHerd else { return }
                showingExceptionPicker = false
                showingUnfinishedConfirmation = false
                showingError = false
                dismiss()
            }
            .sheet(isPresented: $showingExceptionPicker) {
                if isViewingOriginatingHerd {
                    WorkingFinishExceptionSelectionView(
                        items: orderedItems,
                        selection: $exceptionAnimalIDs
                    )
                }
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
                if isViewingOriginatingHerd {
                    WorkingFinishSessionActionBar(
                        isEnabled: canFinish,
                        statusText: finishStatusText,
                        onFinish: finishTapped
                    )
                }
            }
            .alert("Can’t Finish Session", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? viewModel.errorMessage ?? "Unknown error")
            }
            .onChange(of: viewModel.errorMessage) { _, newValue in
                if newValue != nil && isViewingOriginatingHerd &&
                   viewModel.sessionLoadState != .failed {
                    showingError = true
                }
            }
        }
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
            LabeledContent(
                requiresExplicitDestinationForEveryItem
                    ? "Original Source"
                    : "Return All Animals To"
            ) {
                Text(
                    requiresExplicitDestinationForEveryItem
                        ? (session?.sourcePastureName ?? "Source Pasture")
                        : (liveSourcePastureName ?? "Source Pasture")
                )
                .fontWeight(.semibold)
            }
        } header: {
            Text("Default Return")
        } footer: {
            if requiresExplicitDestinationForEveryItem {
                Text("The original source pasture is no longer available. Choose a live destination for every animal below.")
            } else {
                Text("Every animal returns to the source pasture unless it is selected as an exception below.")
            }
        }
    }

    private var exceptionSection: some View {
        Section {
            Button {
                showingExceptionPicker = true
            } label: {
                HStack {
                    Label(
                        requiresExplicitDestinationForEveryItem
                            ? "Choose Destinations for Animals"
                            : "Choose Animals Moving Elsewhere",
                        systemImage: "arrow.triangle.branch"
                    )
                    Spacer()
                    Text("\(exceptionAnimalIDs.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .disabled(
                orderedItems.isEmpty
                    || otherPastures.isEmpty
                    || isFinishing
            )

            if selectedExceptionItems.isEmpty {
                Text(
                    !viewModel.hasLoadedPastureOptions
                        ? "Pasture destinations are unavailable until loading succeeds."
                        : (otherPastures.isEmpty
                            ? "No live destination pastures are available."
                            : (requiresExplicitDestinationForEveryItem
                                ? "Every animal needs a destination."
                                : "No destination exceptions."))
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
            if requiresExplicitDestinationForEveryItem {
                Text("Every animal must have a live destination because the original source pasture is no longer available.")
            } else if !selectedExceptionItems.isEmpty {
                Text("Only animals listed here will move somewhere other than the source pasture.")
            }
        }
    }

    private var sessionLoadRecoverySection: some View {
        Section {
            if viewModel.sessionLoadState == .missing {
                Text("This Working session is not available in the selected Herd. It may still be importing or may have been removed.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Working session details could not be read. Retry after the Herd finishes importing.")
                    .foregroundStyle(.secondary)
            }

            Button {
                guard isViewingOriginatingHerd else { return }
                viewModel.retrySession()
                if viewModel.sessionLoadState == .ready {
                    // Rebuild assignments from the newly read session even
                    // when SwiftUI coalesces nil → same-ID observation changes.
                    seedExceptions(force: true)
                    revalidateExceptionDestinationsAgainstLivePastures()
                }
            } label: {
                Label("Retry Loading Session", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Session Unavailable")
        }
    }

    private var pastureLoadRecoverySection: some View {
        Section {
            Button {
                viewModel.retryPastureOptions()
            } label: {
                Label("Retry Loading Pastures", systemImage: "arrow.clockwise")
            }
        } footer: {
            Text("Saved destination assignments are preserved until live pasture data can be loaded.")
        }
    }

    private var unfinishedSection: some View {
        Section {
            ForEach(unfinishedItems) { item in
                WorkingFinishAnimalStatusRow(item: item)
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

        let livePastureIDs = Set(viewModel.pastures.map(\.id))
        let pastureOptionsAreAuthoritative = viewModel.hasLoadedPastureOptions

        if requiresExplicitDestinationForEveryItem {
            exceptionAnimalIDs = Set(session.queueItems.map(\.id))
            exceptionDestinationIDs = Dictionary(
                uniqueKeysWithValues: session.queueItems.compactMap { item in
                    guard let destinationID = item.destinationPastureID,
                          !pastureOptionsAreAuthoritative || livePastureIDs.contains(destinationID) else {
                        return nil
                    }
                    return (item.id, destinationID)
                }
            )
            return
        }

        let existingExceptions = session.queueItems.filter { item in
            guard let destinationID = item.destinationPastureID else { return false }
            return destinationID != liveSourcePastureID
        }

        exceptionAnimalIDs = Set(existingExceptions.map(\.id))
        exceptionDestinationIDs = Dictionary(
            uniqueKeysWithValues: existingExceptions.compactMap { item in
                guard let destinationID = item.destinationPastureID,
                      !pastureOptionsAreAuthoritative || livePastureIDs.contains(destinationID) else {
                    return nil
                }
                return (item.id, destinationID)
            }
        )
    }

    private func synchronizeExceptionDestinations() {
        exceptionDestinationIDs = exceptionDestinationIDs.filter {
            exceptionAnimalIDs.contains($0.key)
        }

        let livePastureIDs = Set(viewModel.pastures.map(\.id))
        for item in selectedExceptionItems
            where exceptionDestinationIDs[item.id] == nil
        {
            if let existingDestination = item.destinationPastureID,
               existingDestination != liveSourcePastureID,
               (!viewModel.hasLoadedPastureOptions || livePastureIDs.contains(existingDestination)) {
                exceptionDestinationIDs[item.id] = existingDestination
            }
        }
    }

    private func revalidateExceptionDestinationsAgainstLivePastures() {
        guard viewModel.hasLoadedPastureOptions else { return }

        let livePastureIDs = Set(viewModel.pastures.map(\.id))
        exceptionDestinationIDs = exceptionDestinationIDs.filter {
            exceptionAnimalIDs.contains($0.key) && livePastureIDs.contains($0.value)
        }
        synchronizeExceptionDestinations()
    }

    private func destinationBinding(for itemID: UUID) -> Binding<UUID?> {
        Binding(
            get: { exceptionDestinationIDs[itemID] },
            set: { exceptionDestinationIDs[itemID] = $0 }
        )
    }

    private func completeSession() {
        guard !isFinishing, canFinish, isViewingOriginatingHerd else { return }

        let assignments = orderedItems.map { item in
            let destinationPastureID = exceptionAnimalIDs.contains(item.id)
                ? exceptionDestinationIDs[item.id]
                : liveSourcePastureID

            return WorkingQueueDestinationAssignment(
                queueItemID: item.id,
                destinationPastureID: destinationPastureID
            )
        }

        isFinishing = true
        Task { @MainActor in
            defer { isFinishing = false }

            do {
                guard try await viewModel.finishSession(
                    assignments: assignments,
                    originatingHerdID: originatingHerdID,
                    originatingSelectionRevision: originatingSelectionRevision,
                    currentHerdSelection: herdSelection,
                    repository: repository
                ) else { return }
                dismiss()
            } catch {
                guard !Task.isCancelled,
                      herdSelection.currentHerdID == originatingHerdID,
                      herdSelection.selectionRevision == originatingSelectionRevision else { return }
                errorMessage = UserVisibleErrorMessage.make(error)
                showingError = true
            }
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
                    .readableAccentForeground()
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
    let items: [WorkingQueueItemSnapshot]
    @Binding var selection: Set<UUID>
    @State private var searchText = ""

    private var filteredItems: [WorkingQueueItemSnapshot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }

        return items.filter {
            ($0.animalDisplayTagNumber ?? "")
                .localizedCaseInsensitiveContains(query)
                || $0.animalSex.label.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                ForEach(filteredItems) { item in
                    WorkingFinishAnimalStatusRow(item: item)
                        .tag(item.id)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Destination Exceptions")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search tag")
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
        }
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
