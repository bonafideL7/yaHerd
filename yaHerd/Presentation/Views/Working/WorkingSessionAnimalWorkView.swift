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

    var vaccinationRepository: any WorkingTreatmentTemplateCreating {
        workingDependencies.treatmentTemplateCreator
    }

    @StateObject var viewModel: WorkingQueueItemEditorViewModel
    @State var treatmentEntries: [WorkingAnimalTreatmentEntry] = []
    @State var availablePastures: [PastureOption] = []
    @State var selectedDestinationPastureID: UUID?
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
            viewModel.configure(repository: repository)
            viewModel.load()
            loadPastures()
            seedStateIfNeeded()
        }
        .onChange(of: viewModel.snapshot?.id) { _, _ in
            seedStateIfNeeded()
        }
        .onChange(of: estimatedDaysText) { _, _ in
            recalculateDueDate()
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
}
