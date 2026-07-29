import SwiftUI

extension WorkingSessionAnimalWorkView {
    @ToolbarContentBuilder
    var workToolbar: some ToolbarContent {
        if hasWorkData || treatmentEntries.contains(where: \.isPlanned) {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let snapshot, treatmentEntries.contains(where: \.isPlanned) {
                        Button {
                            sessionVaccinationName = defaultSessionVaccinationName(snapshot)
                            showingSaveSessionVaccination = true
                        } label: {
                            Label("Save Session to Vaccinations", systemImage: "square.and.arrow.down")
                        }
                    }

                    if hasWorkData {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete Work Data", systemImage: "trash")
                        }
                        .disabled(!allowsEditing)
                    }
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

    func loadPastures() {
        do {
            availablePastures = try pastureRepository.fetchPastureOptions()
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }

    func seedStateIfNeeded() {
        guard let snapshot, seededSnapshotID != snapshot.id else { return }
        seededSnapshotID = snapshot.id

        let recordsByTreatmentID = Dictionary(
            grouping: snapshot.treatmentRecords,
            by: \.treatmentItemID
        )
        let plannedIDs = Set(snapshot.plannedTreatments.map(\.id))
        var seededEntries = snapshot.plannedTreatments.map { treatment in
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
                    ?? (defaultsToGiven ? treatment.suggestedDose : WorkingTreatmentDose()),
                isPlanned: true
            )
        }

        let oneOffRecords = snapshot.treatmentRecords
            .filter { !plannedIDs.contains($0.treatmentItemID) }
            .reduce(into: [UUID: WorkingTreatmentRecordSnapshot]()) { result, record in
                if let existing = result[record.treatmentItemID], existing.date >= record.date {
                    return
                }
                result[record.treatmentItemID] = record
            }
            .values
            .sorted { $0.date < $1.date }

        seededEntries.append(contentsOf: oneOffRecords.map { record in
            WorkingAnimalTreatmentEntry(
                id: record.treatmentItemID,
                name: record.itemName,
                given: record.given,
                dose: record.dose,
                isPlanned: false
            )
        })

        treatmentEntries = seededEntries
        selectedDestinationPastureID = snapshot.destinationPastureID
        recordPregnancyCheck = snapshot.pregnancyCheck != nil
        pregnancyResult = snapshot.pregnancyCheck?.result ?? .unknown
        estimatedDaysText = snapshot.pregnancyCheck?.estimatedDaysPregnant.map { String($0) } ?? ""
        dueDate = snapshot.pregnancyCheck?.dueDate ?? snapshot.sessionDate
        selectedSire = snapshot.pregnancyCheck?.sire
        castrationPerformed = snapshot.castrationPerformedInSession
        observationNotes = snapshot.observationNotes
    }

    func addTreatmentToSession(at index: Int) {
        guard allowsEditing,
              let snapshot,
              treatmentEntries.indices.contains(index) else {
            return
        }

        let entry = treatmentEntries[index]
        let trimmedName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let item = WorkingTreatmentPlanItem(
            id: entry.id,
            name: trimmedName,
            suggestedDose: entry.dose
        )
        let currentItems = snapshot.plannedTreatments
        let updatedItems = currentItems.contains(where: { $0.id == item.id })
            ? currentItems
            : currentItems + [item]

        do {
            try repository.updateSessionTreatments(
                id: snapshot.sessionID,
                plannedTreatments: updatedItems
            )
            treatmentEntries[index].name = trimmedName
            treatmentEntries[index].isPlanned = true
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }

    func saveSessionVaccinations() {
        guard snapshot != nil else { return }
        let name = sessionVaccinationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = treatmentEntries.compactMap { entry -> WorkingTreatmentPlanItem? in
            guard entry.isPlanned else { return nil }
            let itemName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !itemName.isEmpty else { return nil }
            return WorkingTreatmentPlanItem(
                id: entry.id,
                name: itemName,
                suggestedDose: entry.dose
            )
        }
        guard !name.isEmpty, !items.isEmpty else { return }

        do {
            _ = try vaccinationRepository.createTemplate(
                name: name,
                items: items
            )
            savedVaccinationName = name
        } catch {
            errorMessage = UserVisibleErrorMessage.make(error)
            showingError = true
        }
    }

    func defaultSessionVaccinationName(_ snapshot: WorkingQueueItemEditorSnapshot) -> String {
        let date = snapshot.sessionDate.formatted(
            .dateTime.year().month(.abbreviated).day()
        )
        return "\(snapshot.sessionSourcePastureName ?? "Working Session") \(date)"
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

        let treatmentInputs = treatmentEntries.compactMap { entry -> WorkingTreatmentEntryInput? in
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            guard entry.isPlanned || entry.given else { return nil }
            return WorkingTreatmentEntryInput(
                date: snapshot.sessionDate,
                treatmentItemID: entry.id,
                itemName: name,
                given: entry.given,
                dose: entry.dose
            )
        }

        let input = WorkingSessionAnimalEditInput(
            status: .done,
            completedAt: snapshot.completedAt ?? snapshot.sessionDate,
            destinationPastureID: selectedDestinationPastureID,
            treatmentEntries: treatmentInputs,
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
    var isPlanned: Bool
}
