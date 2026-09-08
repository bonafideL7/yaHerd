import SwiftUI

extension WorkingSessionAnimalWorkView {
    func workForm(_ snapshot: WorkingQueueItemEditorSnapshot) -> some View {
        Form {
            if isSessionLocked {
                lockedSessionSection
            }

            animalSection(snapshot)
            destinationSection(snapshot)
            treatmentSection

            if showsPregnancySection {
                pregnancySection
            }

            if isMale {
                castrationSection
            }

            observationSection
        }
    }

    var lockedSessionSection: some View {
        Section {
            Label {
                Text("This completed session is read-only. Reopen the session to make changes.")
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    func animalSection(_ snapshot: WorkingQueueItemEditorSnapshot) -> some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                if let tagNumber = snapshot.animalDisplayTagNumber {
                    let tagDefinition = tagColorLibrary.resolvedDefinition(
                        tagColorID: snapshot.animalDisplayTagColorID
                    )
                    let damTagDefinition = tagColorLibrary.resolvedDefinition(
                        tagColorID: snapshot.animalDamDisplayTagColorID
                    )

                    AnimalTagView(
                        tagNumber: tagNumber,
                        color: tagDefinition.color,
                        colorName: tagDefinition.name,
                        size: .prominent,
                        damTagNumber: snapshot.animalDamDisplayTagNumber,
                        damTagColor: damTagDefinition.color,
                        damTagColorName: damTagDefinition.name
                    )
                } else {
                    Text("Missing Animal")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(snapshot.animalSex.label)
                    Text(snapshot.sessionDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if allowsEditing {
                Button {
                    showingTagReplacement = true
                } label: {
                    Label(
                        hasCurrentTag ? "Replace Tag" : "Add Tag",
                        systemImage: hasCurrentTag ? "tag.fill" : "tag"
                    )
                }
                .disabled(snapshot.animalID == nil)
            }
        } footer: {
            if isSessionLocked {
                Text("Tag changes are locked with the completed session.")
            } else if hasCurrentTag {
                Text("Replacing the tag retires the current tag and keeps it in the animal’s tag history. The new tag becomes primary.")
            } else {
                Text("The new tag becomes the animal’s primary tag.")
            }
        }
    }

    func destinationSection(_ snapshot: WorkingQueueItemEditorSnapshot) -> some View {
        let canUseSourcePasture = WorkingQueueEditorIdentity.canUseSourcePasture(
            sourcePastureReference
        )

        return Section {
            Picker("Destination After Session", selection: destinationPastureSelectionBinding) {
                if canUseSourcePasture {
                    Text("Return to \(sessionSourcePastureDisplayName)")
                        .tag(Optional<UUID>.none)
                }
                ForEach(availablePastures) { pasture in
                    Text(pasture.name).tag(Optional(pasture.id))
                }
            }
            .disabled(!allowsEditing)

            if destinationSelectionRequiresReview && allowsEditing && canUseSourcePasture {
                Button("Use Source Pasture") {
                    selectedDestinationPastureID = nil
                    destinationSelectionRequiresReview = false
                    errorMessage = nil
                }
            }
        } header: {
            Text("Pasture")
        } footer: {
            if destinationSelectionRequiresReview && !canUseSourcePasture {
                Text("The source pasture is no longer available. Choose another pasture before saving.")
            } else if destinationSelectionRequiresReview {
                Text("The previous pasture selection changed or is no longer available. Choose another pasture or confirm the current source pasture before saving.")
            } else if canUseSourcePasture {
                Text("Choose a different pasture for this animal, or leave the source pasture selected. The move is applied when the session is finished.")
            } else {
                Text("Choose a destination pasture before saving.")
            }
        }
    }

    var destinationPastureSelectionBinding: Binding<UUID?> {
        Binding(
            get: { selectedDestinationPastureID },
            set: { newValue in
                selectedDestinationPastureID = newValue

                if newValue == nil,
                   !WorkingQueueEditorIdentity.canUseSourcePasture(sourcePastureReference) {
                    destinationSelectionRequiresReview = true
                    errorMessage = "The source pasture is no longer available. Choose another pasture before saving."
                    return
                }

                destinationSelectionRequiresReview = false
                errorMessage = nil
            }
        )
    }

    var treatmentSection: some View {
        Section {
            if treatmentEntries.isEmpty {
                Text("No vaccinations or treatments yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(treatmentEntries.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 12) {
                        if treatmentEntries[index].isPlanned {
                            Toggle(
                                treatmentEntries[index].name,
                                isOn: $treatmentEntries[index].given
                            )
                            .disabled(!allowsEditing)
                        } else {
                            TextField(
                                "Vaccination, medication, or treatment",
                                text: $treatmentEntries[index].name
                            )
                            .textFieldStyle(.roundedBorder)
                            .disabled(!allowsEditing)

                            Toggle("Given", isOn: $treatmentEntries[index].given)
                                .disabled(!allowsEditing)
                        }

                        if treatmentEntries[index].given || !treatmentEntries[index].dose.isEmpty {
                            WorkingTreatmentDoseEditor(
                                dose: $treatmentEntries[index].dose,
                                isEnabled: allowsEditing && treatmentEntries[index].given
                            )
                        }

                        if !treatmentEntries[index].isPlanned && allowsEditing {
                            HStack {
                                Button {
                                    addTreatmentToSession(at: index)
                                } label: {
                                    Label("Use for Remaining Animals", systemImage: "person.3")
                                }
                                .disabled(
                                    treatmentEntries[index].name
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                        .isEmpty
                                )

                                Spacer()

                                Button("Remove", role: .destructive) {
                                    treatmentEntries.remove(at: index)
                                }
                            }
                            .font(.footnote)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if allowsEditing {
                Button {
                    treatmentEntries.append(
                        WorkingAnimalTreatmentEntry(
                            id: UUID(),
                            name: "",
                            given: true,
                            dose: WorkingTreatmentDose(),
                            isPlanned: false
                        )
                    )
                } label: {
                    Label("Add One-Off Vaccination or Treatment", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Vaccinations & Treatments")
        } footer: {
            Text(
                isSessionLocked
                    ? "Recorded vaccinations and treatments for this completed session."
                    : "One-off entries apply only to this animal. Use for Remaining Animals adds the item to the active session without requiring advance setup."
            )
        }
    }

    var pregnancySection: some View {
        Section("Pregnancy Check") {
            Toggle("Record Pregnancy Check", isOn: $recordPregnancyCheck)
                .disabled(!allowsEditing)

            if recordPregnancyCheck {
                Picker("Result", selection: $pregnancyResult) {
                    ForEach(PregnancyResult.allCases, id: \.self) { result in
                        Text(result.rawValue.capitalized).tag(result)
                    }
                }
                .disabled(!allowsEditing)

                if pregnancyResult == .pregnant {
                    LabeledContent("Estimated Days") {
                        TextField("Optional", text: estimatedDaysBinding)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 120)
                            .disabled(!allowsEditing)
                    }

                    DatePicker(
                        "Due Date",
                        selection: $dueDate,
                        displayedComponents: .date
                    )
                    .disabled(!allowsEditing)

                    Button {
                        showingSirePicker = true
                    } label: {
                        HStack {
                            Text("Sire")
                            Spacer()
                            if let selectedSire {
                                let definition = tagColorLibrary.resolvedDefinition(
                                    tagColorID: selectedSire.displayTagColorID
                                )
                                AnimalTagView(
                                    tagNumber: selectedSire.displayTagNumber,
                                    color: definition.color,
                                    colorName: definition.name,
                                    size: .compact
                                )
                            } else {
                                Text("Choose")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!allowsEditing)
                }
            }
        }
    }

    var castrationSection: some View {
        Section("Procedures") {
            Toggle("Castration Performed", isOn: $castrationPerformed)
                .disabled(!allowsEditing)
        }
    }

    var observationSection: some View {
        Section("Observations") {
            TextField("Notes", text: $observationNotes, axis: .vertical)
                .disabled(!allowsEditing)
        }
    }
}
