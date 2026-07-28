import SwiftUI

extension WorkingSessionAnimalWorkView {
    @ToolbarContentBuilder
    var workToolbar: some ToolbarContent {
        if hasWorkData {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Work Data", systemImage: "trash")
                    }
                    .disabled(!allowsEditing)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Animal Work Actions")
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            if isExistingWork {
                ToolbarSaveButton {
                    saveWork()
                }
                .disabled(snapshot?.animalID == nil || !allowsEditing)
            } else {
                ToolbarDoneButton {
                    saveWork()
                }
                .disabled(snapshot?.animalID == nil || !allowsEditing)
            }
        }
    }

    var tagReplacementSheet: some View {
        AnimalTagEditView(
            initialNumber: "",
            initialColorID: snapshot?.animalDisplayTagColorID ?? tagColorLibrary.defaultColorID,
            title: hasCurrentTag ? "Replace Tag" : "Add Tag",
            saveButtonTitle: hasCurrentTag ? "Replace Tag" : "Add Tag",
            showsPrimaryToggle: false,
            requiresNumber: true
        ) { number, colorID, _ in
            guard allowsEditing else { return }
            viewModel.replacePrimaryTag(number: number, colorID: colorID)
        }
    }

    var sirePickerSheet: some View {
        AnimalParentPickerView(
            title: "Select Sire",
            excludeAnimalID: snapshot?.animalID,
            suggestedSexes: [.male]
        ) { selected in
            guard allowsEditing else { return }
            selectedSire = selected
        }
    }

    func seedStateIfNeeded() {
        guard let snapshot, seededSnapshotID != snapshot.id else { return }
        seededSnapshotID = snapshot.id

        let recordsByTreatmentID = Dictionary(
            grouping: snapshot.treatmentRecords,
            by: \.treatmentItemID
        )
        treatmentEntries = snapshot.plannedTreatments.map { treatment in
            let existing = recordsByTreatmentID[treatment.id]?
                .sorted { $0.date > $1.date }
                .first
            let defaultsToGiven =
                snapshot.sessionStatus == .active
                    && snapshot.status != .done

            return WorkingAnimalTreatmentEntry(
                id: treatment.id,
                name: treatment.name,
                given: existing?.given ?? defaultsToGiven,
                dose: existing?.dose
                    ?? (defaultsToGiven ? treatment.suggestedDose : WorkingTreatmentDose())
            )
        }

        recordPregnancyCheck = snapshot.pregnancyCheck != nil
        pregnancyResult = snapshot.pregnancyCheck?.result ?? .unknown
        estimatedDaysText = snapshot.pregnancyCheck?.estimatedDaysPregnant.map { String($0) } ?? ""
        dueDate = snapshot.pregnancyCheck?.dueDate ?? snapshot.sessionDate
        selectedSire = snapshot.pregnancyCheck?.sire
        castrationPerformed = snapshot.castrationPerformedInSession
        observationNotes = snapshot.observationNotes
    }

    func recalculateDueDate() {
        guard allowsEditing,
              pregnancyResult == .pregnant,
              let snapshot,
              let estimatedDays = Int(
                estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)
              ) else {
            return
        }

        let remainingDays = max(0, WorkingConstants.gestationDays - estimatedDays)
        if let calculatedDate = Calendar.current.date(
            byAdding: .day,
            value: remainingDays,
            to: snapshot.sessionDate
        ) {
            dueDate = calculatedDate
        }
    }

    func saveWork() {
        guard allowsEditing, let snapshot else { return }

        let pregnancyInput: WorkingPregnancyCheckInput?
        if showsPregnancySection,
           recordPregnancyCheck,
           pregnancyResult == .open || pregnancyResult == .pregnant {
            pregnancyInput = WorkingPregnancyCheckInput(
                date: snapshot.sessionDate,
                result: pregnancyResult,
                estimatedDaysPregnant: Int(
                    estimatedDaysText.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                dueDate: pregnancyResult == .pregnant ? dueDate : nil,
                sireAnimalID: selectedSire?.id
            )
        } else {
            pregnancyInput = nil
        }

        let input = WorkingSessionAnimalEditInput(
            status: .done,
            completedAt: snapshot.completedAt ?? snapshot.sessionDate,
            destinationPastureID: snapshot.destinationPastureID,
            treatmentEntries: treatmentEntries.map { entry in
                WorkingTreatmentEntryInput(
                    date: snapshot.sessionDate,
                    treatmentItemID: entry.id,
                    itemName: entry.name,
                    given: entry.given,
                    dose: entry.dose
                )
            },
            pregnancyCheck: pregnancyInput,
            castrationPerformed: isMale
                ? castrationPerformed
                : snapshot.castrationPerformedInSession,
            observationNotes: observationNotes
        )

        do {
            try repository.saveEdits(
                forQueueItemID: snapshot.id,
                inSessionID: snapshot.sessionID,
                input: input
            )
            dismiss()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }

    func deleteWorkData() {
        guard allowsEditing, let snapshot else { return }
        do {
            try repository.deleteWorkData(
                forQueueItemID: snapshot.id,
                inSessionID: snapshot.sessionID
            )
            dismiss()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }
}

struct WorkingAnimalTreatmentEntry: Identifiable {
    let id: UUID
    var name: String
    var given: Bool
    var dose: WorkingTreatmentDose
}
