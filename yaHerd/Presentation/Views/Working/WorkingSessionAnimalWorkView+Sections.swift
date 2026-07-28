import SwiftUI

extension WorkingSessionAnimalWorkView {
    func workForm(_ snapshot: WorkingQueueItemEditorSnapshot) -> some View {
        Form {
            if isSessionLocked {
                lockedSessionSection
            }

            animalSection(snapshot)
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

    var treatmentSection: some View {
        Section {
            if treatmentEntries.isEmpty {
                Text("No planned treatments")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(treatmentEntries.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(
                            treatmentEntries[index].name,
                            isOn: $treatmentEntries[index].given
                        )
                        .disabled(!allowsEditing)

                        WorkingTreatmentDoseEditor(
                            dose: $treatmentEntries[index].dose,
                            isEnabled: allowsEditing && treatmentEntries[index].given
                        )
                    }
                }
            }
        } header: {
            Text("Treatments")
        } footer: {
            if !treatmentEntries.isEmpty {
                Text(
                    isSessionLocked
                        ? "Recorded treatment doses for this completed session."
                        : "Dose amount, unit, and administration route are recorded for this animal and can differ from the treatment template."
                )
            }
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
                        TextField("Optional", text: $estimatedDaysText)
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
