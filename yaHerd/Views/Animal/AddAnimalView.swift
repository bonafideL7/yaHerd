//
//  AddAnimalView.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//


import SwiftUI
import SwiftData

struct AddAnimalView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @State private var tagNumber = ""
	@State private var tagColorID: UUID?
    @State private var sex: Sex = .female
    @State private var birthDate = Date()
    @State private var status: AnimalStatus = .alive
    @State private var sire = ""
    @State private var dam = ""

    @State private var showingSirePicker = false
    @State private var showingDamPicker = false

    @State private var errorMessage: String?
    @State private var showingError = false

    private var tagColorIDBinding: Binding<UUID> {
        Binding(
            get: { tagColorID ?? tagColorLibrary.defaultColor.id },
            set: { tagColorID = $0 }
        )
    }


    var body: some View {
        NavigationStack {
            Form {
                TextField("Tag Number", text: $tagNumber)
				Picker("Tag Color", selection: tagColorIDBinding) {
					ForEach(tagColorLibrary.colors) { def in
						HStack(spacing: 10) {
							TagColorTagIcon(color: def.color, accessibilityLabel: "Tag color: \(def.name)")
							Text("\(def.name) (\(def.prefix))")
						}
						.tag(def.id)
					}
				}

                let selectedDef = tagColorLibrary.definition(for: tagColorIDBinding.wrappedValue) ?? tagColorLibrary.defaultColor
                Text("Tag: \(selectedDef.prefix)\(tagNumber)")
                    .foregroundStyle(.secondary)
                Picker("Sex", selection: $sex) {
                    ForEach(Sex.allCases, id: \.self) { sex in
                        Text(sex.label).tag(sex)
                    }
                }
                    .foregroundStyle(.secondary)
                DatePicker("Birth Date", selection: $birthDate, displayedComponents: .date)
                Picker("Status", selection: $status) {
                    ForEach(AnimalStatus.allCases, id: \.self) { Text($0.rawValue.capitalized) }
                }

                Section("Parents") {
                    HStack {
                        TextField("Sire", text: $sire)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Pick") { showingSirePicker = true }
                    }
                    if !sire.isEmpty {
                        Button("Clear Sire") { sire = "" }
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        TextField("Dam", text: $dam)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Pick") { showingDamPicker = true }
                    }
                    if !dam.isEmpty {
                        Button("Clear Dam") { dam = "" }
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Animal")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { validateAndSave() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: { dismiss() })
                }
            }
            .alert("Validation Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .sheet(isPresented: $showingSirePicker) {
            AnimalParentPickerView(
                title: "Select Sire",
                excludeAnimal: nil,
                suggestedSexes: [.male]
            ) { picked in
                sire = picked.tagNumber
            }
        }
        .sheet(isPresented: $showingDamPicker) {
            AnimalParentPickerView(
                title: "Select Dam",
                excludeAnimal: nil,
                suggestedSexes: [.female]
            ) { picked in
                dam = picked.tagNumber
            }
        }
    }

    private func validateAndSave() {
        do {
			let animal = Animal(
				tagNumber: tagNumber,
				tagColorID: tagColorIDBinding.wrappedValue,
                birthDate: birthDate,
                status: status,
                sire: sire.isEmpty ? nil : sire,
                dam: dam.isEmpty ? nil : dam
            )

            context.insert(animal)
            dismiss()
        }
    }
}
