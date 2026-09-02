import SwiftUI

struct WorkingSessionAnimalWorkView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.workingSessionFeatureDependencies) var workingDependencies
    @Environment(\.appDataAccessMode) var dataAccessMode
    @EnvironmentObject var tagColorLibrary: TagColorLibraryStore

    var repository: any WorkingQueueItemEditingRepository {
        workingDependencies.queueItemEditingRepository
    }

    var pastureRepository: any PastureReferenceDataReader {
        workingDependencies.pastureReferenceReader
    }

    var animalSummaryReader: any AnimalSummaryReading {
        workingDependencies.animalSummaryReader
    }

    var vaccinationRepository: any WorkingTreatmentTemplateCreating {
        workingDependencies.treatmentTemplateCreator
    }

    @StateObject var viewModel: WorkingQueueItemEditorViewModel
    @State var treatmentEntries: [WorkingAnimalTreatmentEntry] = []
    @State var availablePastures: [PastureOption] = []
    @State var selectedDestinationPastureID: UUID?
    @State var sourcePastureReference: WorkingQueueEditorSourcePastureReference?
    @State var destinationSelectionRequiresReview = false
    @State var recordPregnancyCheck = false
    @State var pregnancyResult: PregnancyResult = .unknown
    @State var estimatedDaysText = ""
    @State var dueDate: Date = .now
    @State var automaticallyCalculatedDueDate: Date?
    @State var selectedSire: AnimalParentOption?
    @State var castrationPerformed = false
    @State var observationNotes = ""
    @State var seededSnapshotID: UUID?
    @State var showingSirePicker = false
    @State var showingTagReplacement = false
    @State var showingDeleteConfirmation = false
    @State var showingSaveSessionVaccination = false
    @State var sessionVaccinationName = ""
    @State var savedVaccinationName: String?
    @State var errorMessage: String?
    @State var showingError = false

    init(sessionID: UUID, queueItemID: UUID) {
        _viewModel = StateObject(
            wrappedValue: WorkingQueueItemEditorViewModel(
                sessionID: sessionID,
                queueItemID: queueItemID,
                repository: EmptyWorkingRepository()
            )
        )
    }

    var snapshot: WorkingQueueItemEditorSnapshot? {
        viewModel.snapshot
    }

    var sessionSourcePastureDisplayName: String {
        if let sourcePastureReference {
            return sourcePastureReference.name ?? "Source Pasture"
        }
        return snapshot?.sessionSourcePastureName ?? "Source Pasture"
    }

    var isExistingWork: Bool {
        snapshot?.status == .done
    }

    var isSessionLocked: Bool {
        snapshot?.sessionStatus != .active
    }

    var allowsEditing: Bool {
        dataAccessMode.allowsDataMutations && !isSessionLocked
    }

    var isFemale: Bool {
        snapshot?.animalSex == .female
    }

    var isMale: Bool {
        snapshot?.animalSex == .male
    }

    var showsPregnancySection: Bool {
        guard let snapshot else { return false }
        return isFemale && snapshot.animalAgeInMonths >= WorkingConstants.pregCheckEligibleMonths
    }

    var hasCurrentTag: Bool {
        guard let number = snapshot?.animalDisplayTagNumber else { return false }
        return !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasWorkData: Bool {
        guard let snapshot else { return false }
        return snapshot.status == .done
            || !snapshot.treatmentRecords.isEmpty
            || snapshot.pregnancyCheck != nil
            || snapshot.castrationPerformedInSession
            || !snapshot.observationNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if let snapshot {
                workForm(snapshot)
            } else if viewModel.errorMessage == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Animal Not Available",
                    systemImage: "tag.slash",
                    description: Text("This animal may no longer be part of the working session.")
                )
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if snapshot != nil && !isSessionLocked {
                workToolbar
            }
        }
        .task {
            let mutationStream = workingDependencies.mutationStream
            let startingSequence = mutationStream.currentSequence

            viewModel.configure(repository: repository)
            viewModel.load()
            loadPastures()
            seedStateIfNeeded()
            seedSessionSourcePastureReferenceIfNeeded()

            await observeReferenceDataMutations(
                mutationStream: mutationStream,
                after: startingSequence
            )
        }
        .onChange(of: viewModel.snapshot?.id) { _, _ in
            seedStateIfNeeded()
            seedSessionSourcePastureReferenceIfNeeded()
        }
        .sheet(isPresented: $showingTagReplacement) {
            tagReplacementSheet
        }
        .sheet(isPresented: $showingSirePicker) {
            sirePickerSheet
        }
        .alert("Save Session Vaccinations", isPresented: $showingSaveSessionVaccination) {
            TextField("Vaccination name", text: $sessionVaccinationName)
            Button("Save") {
                saveSessionVaccinations()
            }
            .disabled(sessionVaccinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the vaccinations and treatments currently available in this session for reuse later.")
        }
        .alert("Saved to Vaccinations", isPresented: savedVaccinationBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(savedVaccinationName.map { "\($0) is now available under Vaccinations." } ?? "Saved.")
        }
        .alert("Delete Work Data?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteWorkData()
            }
            .disabled(!allowsEditing)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Treatments, pregnancy checks, procedures, and observations recorded for this animal in this session will be deleted. The animal remains in the session.")
        }
        .alert("Can’t Save", isPresented: $showingError) {
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

    private var navigationTitle: String {
        if isSessionLocked {
            return "Animal Work Review"
        }
        return isExistingWork ? "Edit Animal Work" : "Work Animal"
    }

    private var savedVaccinationBinding: Binding<Bool> {
        Binding(
            get: { savedVaccinationName != nil },
            set: { if !$0 { savedVaccinationName = nil } }
        )
    }

    @MainActor
    private func observeReferenceDataMutations(
        mutationStream: any ApplicationMutationStreaming,
        after startingSequence: UInt64
    ) async {
        for await event in mutationStream.events(after: startingSequence) {
            guard !Task.isCancelled else { return }

            switch event.source {
            case .sharedStoreImport:
                guard !presentedQueueItemWasInvalidatedBySharedImport() else { return }
                guard !refreshSessionSourcePastureAfterMutation() else { return }
                refreshDestinationPasturesAfterMutation()
                revalidateSelectedSireAfterMutation()
            case .local(.sampleData):
                guard !refreshSessionSourcePastureAfterMutation() else { return }
                refreshDestinationPasturesAfterMutation()
                revalidateSelectedSireAfterMutation()
            case .local(.pasture):
                guard !refreshSessionSourcePastureAfterMutation() else { return }
                refreshDestinationPasturesAfterMutation()
            case .local(.animal):
                revalidateSelectedSireAfterMutation()
            case .publicIDRepair:
                // Duplicate-ID repair can preserve a public UUID while replacing the underlying
                // local queue object. Every presentation of this editor must therefore tear down
                // its transient draft rather than remaining bound to an indeterminate identity.
                guard snapshot != nil else { continue }
                dismiss()
                return
            case .collaborationStateChange, .local:
                break
            }
        }
    }

    @MainActor
    private func presentedQueueItemWasInvalidatedBySharedImport() -> Bool {
        guard let presentedSnapshot = snapshot else { return false }

        do {
            let refreshedSnapshot = try repository.fetchQueueItemEditor(
                sessionID: presentedSnapshot.sessionID,
                queueItemID: presentedSnapshot.id
            )

            guard !WorkingQueueEditorIdentity.invalidates(
                presented: presentedSnapshot,
                refreshed: refreshedSnapshot
            ) else {
                dismiss()
                return true
            }

            return false
        } catch {
            // A transient read failure is not evidence that the identity changed. Keep the draft;
            // persistence still validates explicit references and fails closed on a later save.
            return false
        }
    }

    @MainActor
    private func seedSessionSourcePastureReferenceIfNeeded() {
        guard sourcePastureReference == nil, let snapshot else { return }

        do {
            guard let session = try workingDependencies.sessionDetailRepository.fetchSessionDetail(
                id: snapshot.sessionID
            ) else {
                return
            }
            let sourceReference = WorkingQueueEditorSourcePastureReference(session: session)
            sourcePastureReference = sourceReference
            selectedDestinationPastureID = WorkingQueueEditorIdentity.destinationPastureSelection(
                persistedDestinationPastureID: snapshot.destinationPastureID,
                sourcePasture: sourceReference
            )

            if selectedDestinationPastureID == nil,
               !WorkingQueueEditorIdentity.canUseSourcePasture(sourceReference) {
                destinationSelectionRequiresReview = true
            }
        } catch {
            // The editor snapshot still provides the source-pasture label. If a later mutation
            // arrives without a durable baseline, source selection is conservatively re-reviewed.
        }
    }

    @MainActor
    private func refreshSessionSourcePastureAfterMutation() -> Bool {
        guard let snapshot else { return false }

        do {
            guard let session = try workingDependencies.sessionDetailRepository.fetchSessionDetail(
                id: snapshot.sessionID
            ) else {
                dismiss()
                return true
            }

            let refreshedReference = WorkingQueueEditorSourcePastureReference(session: session)
            let requiresReview = WorkingQueueEditorIdentity.sourcePastureChangeRequiresReview(
                presented: sourcePastureReference,
                refreshed: refreshedReference,
                selectedDestinationPastureID: selectedDestinationPastureID
            )
            sourcePastureReference = refreshedReference

            guard requiresReview else { return false }

            destinationSelectionRequiresReview = true
            errorMessage = "The source pasture changed while you were editing. Confirm the current source pasture or choose another pasture before saving."
            showingError = true
            return false
        } catch {
            // Preserve the current draft when the session cannot be refreshed transiently. The
            // next mutation gets another chance to validate the source-pasture reference.
            return false
        }
    }

    @MainActor
    private func refreshDestinationPasturesAfterMutation() {
        do {
            let refreshedPastures = try pastureRepository.fetchPastureOptions()
            availablePastures = refreshedPastures

            guard let selectedDestinationPastureID,
                  !refreshedPastures.contains(where: { $0.id == selectedDestinationPastureID })
            else {
                return
            }

            self.selectedDestinationPastureID = nil
            destinationSelectionRequiresReview = true
            errorMessage = "The selected destination pasture is no longer available. Choose another pasture or confirm the source pasture before saving."
            showingError = true
        } catch {
            // Preserve the in-progress draft and current selection when reference data cannot be
            // refreshed. The repository still rejects a missing explicit pasture ID at save time.
        }
    }

    @MainActor
    private func revalidateSelectedSireAfterMutation() {
        guard let selectedSire else { return }

        do {
            let animalStillExists = try animalSummaryReader.fetchAnimals()
                .contains(where: { $0.id == selectedSire.id })
            guard !animalStillExists else { return }

            self.selectedSire = nil
            errorMessage = "The selected sire is no longer available. Choose another sire if you want to record one before saving."
            showingError = true
        } catch {
            // Keep the user's current selection when reference data cannot be refreshed. The
            // repository validates a non-nil sire ID before mutating work data and fails closed.
        }
    }
}
