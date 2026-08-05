//
//  WorkingSessionDetailView.swift
//  yaHerd
//

import SwiftUI

struct WorkingSessionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.workingSessionFeatureDependencies) private var workingDependencies
    @Environment(\.appDataAccessMode) private var dataAccessMode
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    private var repository: any WorkingSessionDetailRepository {
        workingDependencies.sessionDetailRepository
    }

    @StateObject private var viewModel: WorkingSessionDetailViewModel
    @State private var animalFilter: WorkingSessionAnimalFilter = .remaining
    @State private var searchText = ""
    @State private var showingAddAnimals = false
    @State private var showingFinish = false
    @State private var showingDeleteAlert = false
    @State private var showingReopenConfirmation = false
    @State private var errorMessage: String?
    @State private var showingError = false

    init(sessionID: UUID) {
        _viewModel = StateObject(
            wrappedValue: WorkingSessionDetailViewModel(
                sessionID: sessionID,
                repository: EmptyWorkingRepository()
            )
        )
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredItems: [WorkingQueueItemSnapshot] {
        guard let session = viewModel.session else { return [] }

        let statusFiltered = session.queueItems.filter { item in
            animalFilter.includes(item.status)
        }
        return searchItems(statusFiltered.sorted(by: animalSortOrder))
    }

    private var completedReviewItems: [WorkingQueueItemSnapshot] {
        guard let session = viewModel.session else { return [] }
        return searchItems(session.queueItems.sorted(by: animalSortOrder))
    }

    var body: some View {
        Group {
            if let session = viewModel.session {
                sessionContent(session)
            } else if viewModel.hasLoaded {
                ContentUnavailableView(
                    "Session Not Found",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("This working session may have been deleted.")
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(viewModel.session?.sourcePastureName ?? "Working Session")
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(navigationSubtitle)
        .toolbar {
            if let session = viewModel.session {
                sessionToolbar(session)
            }
        }
        .task {
            viewModel.configure(repository: repository)
            await viewModel.observe(
                mutationStream: workingDependencies.mutationStream,
                didLoad: resetFilterForCompletedSession
            )
        }
        .sheet(isPresented: $showingAddAnimals, onDismiss: reload) {
            if let session = viewModel.session {
                WorkingCollectAnimalsView(sessionID: session.id)
            }
        }
        .sheet(isPresented: $showingFinish, onDismiss: reload) {
            if let session = viewModel.session {
                WorkingFinishSessionView(sessionID: session.id)
            }
        }
        .confirmationDialog(
            "Reopen Working Session?",
            isPresented: $showingReopenConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reopen Session") {
                reopenSession()
            }
            .disabledWhenDataReadOnly()
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The session will become editable again. Animals remain in their current pastures and are not automatically returned to the working pen.")
        }
        .alert("Delete Working Session?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteSession()
            }
            .disabledWhenDataReadOnly()
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteConfirmationMessage)
        }
        .alert("Can’t Update Session", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? viewModel.errorMessage ?? "Unknown error")
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if newValue != nil {
                showingError = true
            }
        }
    }

    private var navigationSubtitle: String {
        guard let session = viewModel.session else { return "" }
        let dateText = session.date.formatted(date: .abbreviated, time: .omitted)
        switch session.status {
        case .active:
            return dateText
        case .finished:
            return "Completed • \(dateText)"
        case .cancelled:
            return "Cancelled • \(dateText)"
        }
    }

    private var deleteConfirmationMessage: String {
        guard let session = viewModel.session else { return "" }
        if session.status == .active {
            return "Animals in the working pen will return to their source pasture. The session and its recorded work will be deleted."
        }
        return "The completed session and its recorded work will be deleted."
    }

    @ViewBuilder
    private func sessionContent(_ session: WorkingSessionDetailSnapshot) -> some View {
        if session.status == .active {
            activeSessionContent(session)
        } else {
            completedReviewContent(session)
        }
    }

    private func activeSessionContent(_ session: WorkingSessionDetailSnapshot) -> some View {
        List {
            Section {
                WorkingSessionProgressHeader(session: session)
            }

            Section {
                WorkingSessionAnimalFilterRow(
                    selectedFilter: $animalFilter,
                    visibleCount: filteredItems.count,
                    totalCount: session.queueItems.count,
                    hasSearchText: !trimmedSearchText.isEmpty,
                    onReset: resetAnimalFilters
                )

                if filteredItems.isEmpty {
                    emptyAnimalsView(session)
                } else {
                    ForEach(filteredItems) { item in
                        NavigationLink {
                            WorkingSessionAnimalWorkView(
                                sessionID: session.id,
                                queueItemID: item.id
                            )
                            .onDisappear(perform: reload)
                        } label: {
                            WorkingSessionAnimalRow(item: item)
                        }
                    }
                }
            } header: {
                Text(trimmedSearchText.isEmpty ? "Animals" : "Search Results")
            } footer: {
                if trimmedSearchText.isEmpty && !session.queueItems.isEmpty {
                    Text("Remaining animals are shown by default. Select an animal to record or edit its work.")
                }
            }
        }
        .refreshable {
            reload()
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search session animals"
        )
    }

    private func completedReviewContent(_ session: WorkingSessionDetailSnapshot) -> some View {
        List {
            Section {
                WorkingSessionCompletedReviewHeader(session: session)
            }

            completedTreatmentSection(session)
            completedDestinationSection(session)

            Section {
                if completedReviewItems.isEmpty {
                    ContentUnavailableView(
                        trimmedSearchText.isEmpty ? "No Animals" : "No Matching Animals",
                        systemImage: trimmedSearchText.isEmpty ? "tag" : "magnifyingglass",
                        description: Text(
                            trimmedSearchText.isEmpty
                                ? "This session does not contain any animals."
                                : "No completed-session animals match the current search."
                        )
                    )
                } else {
                    ForEach(completedReviewItems) { item in
                        NavigationLink {
                            WorkingSessionAnimalWorkView(
                                sessionID: session.id,
                                queueItemID: item.id
                            )
                            .onDisappear(perform: reload)
                        } label: {
                            WorkingSessionAnimalRow(
                                item: item,
                                showsDestination: true
                            )
                        }
                    }
                }
            } header: {
                Text(trimmedSearchText.isEmpty ? "Animal Results" : "Search Results")
            } footer: {
                Text("Completed sessions are read-only. Reopen the session to change animal work, tags, or destinations.")
            }
        }
        .refreshable {
            reload()
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search completed session"
        )
    }

    @ViewBuilder
    private func completedTreatmentSection(_ session: WorkingSessionDetailSnapshot) -> some View {
        Section {
            if session.plannedTreatments.isEmpty {
                Text("No planned treatments")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.plannedTreatments) { treatment in
                    LabeledContent(treatment.name) {
                        Text(
                            treatment.suggestedDose.isEmpty
                                ? "Variable"
                                : treatment.suggestedDose.formattedDescription
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Treatment Plan")
        }
    }

    private func completedDestinationSection(_ session: WorkingSessionDetailSnapshot) -> some View {
        let grouped = Dictionary(grouping: session.queueItems) { item in
            item.destinationPastureName
                ?? session.sourcePastureName
                ?? "No Pasture"
        }

        return Section {
            ForEach(grouped.keys.sorted(), id: \.self) { pastureName in
                LabeledContent(pastureName) {
                    Text("\(grouped[pastureName]?.count ?? 0)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Returned To")
        }
    }

    @ViewBuilder
    private func emptyAnimalsView(_ session: WorkingSessionDetailSnapshot) -> some View {
        if session.queueItems.isEmpty {
            ContentUnavailableView(
                "No Animals",
                systemImage: "tag",
                description: Text("Add animals to this working session to begin recording work.")
            )

            if dataAccessMode.allowsDataMutations {
                Button {
                    showingAddAnimals = true
                } label: {
                    Label("Add Animals", systemImage: "tag.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
            }
        } else {
            ContentUnavailableView(
                emptyFilterTitle,
                systemImage: trimmedSearchText.isEmpty ? animalFilter.systemImage : "magnifyingglass",
                description: Text(emptyFilterDescription)
            )

            Button {
                resetAnimalFilters()
            } label: {
                Label("Show All Animals", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.bordered)
        }
    }

    private var emptyFilterTitle: String {
        if !trimmedSearchText.isEmpty { return "No Matching Animals" }
        switch animalFilter {
        case .remaining:
            return "No Remaining Animals"
        case .all:
            return "No Animals"
        case .completed:
            return "No Completed Animals"
        }
    }

    private var emptyFilterDescription: String {
        if !trimmedSearchText.isEmpty {
            return "No session animals match the current search and filter."
        }
        switch animalFilter {
        case .remaining:
            return "Every animal in this session has been worked."
        case .all:
            return "This session does not contain any animals."
        case .completed:
            return "No animals have been marked worked yet."
        }
    }

    @ToolbarContentBuilder
    private func sessionToolbar(_ session: WorkingSessionDetailSnapshot) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if session.status == .active {
                Button {
                    showingAddAnimals = true
                } label: {
                    Label("Add Animals", systemImage: "tag.badge.plus")
                }
                .accessibilityLabel("Add Animals")
                .disabled(session.sourcePastureID == nil || !dataAccessMode.allowsDataMutations)

                Button {
                    showingFinish = true
                } label: {
                    Text(remainingItemCount(in: session) == 0 ? "Finish" : "Review")
                }
                .tint(remainingItemCount(in: session) == 0 ? Color.accentColor : Color.orange)
                .disabled(session.queueItems.isEmpty || !dataAccessMode.allowsDataMutations)
            }

            Menu {
                if session.status == .finished {
                    Button {
                        showingReopenConfirmation = true
                    } label: {
                        Label("Reopen Session", systemImage: "lock.open")
                    }
                    .disabled(!dataAccessMode.allowsDataMutations)
                }

                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete Session", systemImage: "trash")
                }
                .disabled(!dataAccessMode.allowsDataMutations)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Session Actions")
        }
    }

    private func searchItems(
        _ items: [WorkingQueueItemSnapshot]
    ) -> [WorkingQueueItemSnapshot] {
        guard !trimmedSearchText.isEmpty else { return items }

        return items.filter { item in
            guard let tagNumber = item.animalDisplayTagNumber else { return false }
            let formattedTag = tagColorLibrary.formattedTag(
                tagNumber: tagNumber,
                colorID: item.animalDisplayTagColorID
            )
            return tagNumber.localizedCaseInsensitiveContains(trimmedSearchText)
                || formattedTag.localizedCaseInsensitiveContains(trimmedSearchText)
                || item.animalSex.label.localizedCaseInsensitiveContains(trimmedSearchText)
                || (item.destinationPastureName?.localizedCaseInsensitiveContains(trimmedSearchText) ?? false)
        }
    }

    private func animalSortOrder(
        _ left: WorkingQueueItemSnapshot,
        _ right: WorkingQueueItemSnapshot
    ) -> Bool {
        let leftTag = left.animalDisplayTagNumber?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rightTag = right.animalDisplayTagNumber?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if leftTag.isEmpty != rightTag.isEmpty {
            return !leftTag.isEmpty
        }

        let comparison = leftTag.localizedStandardCompare(rightTag)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }

        return left.id.uuidString < right.id.uuidString
    }

    private func resetAnimalFilters() {
        animalFilter = .all
        searchText = ""
    }

    private func remainingItemCount(in session: WorkingSessionDetailSnapshot) -> Int {
        session.queueItems.filter { $0.status != .done }.count
    }

    private func reopenSession() {
        viewModel.reopenSession()
        animalFilter = .all
        searchText = ""
    }

    private func resetFilterForCompletedSession() {
        if viewModel.session?.status != .active {
            animalFilter = .all
        }
    }

    private func reload() {
        viewModel.load()
        resetFilterForCompletedSession()
    }

    private func deleteSession() {
        guard let sessionID = viewModel.session?.id else { return }
        do {
            try repository.deleteSession(id: sessionID)
            dismiss()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }
}
