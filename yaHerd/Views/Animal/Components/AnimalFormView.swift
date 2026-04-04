//
// AnimalFormView.swift
//

import SwiftUI
import SwiftData

enum ParentPickerType: Identifiable {
    case sire
    case dam

    var id: Int {
        switch self {
        case .sire: return 1
        case .dam: return 2
        }
    }
}

struct TagFieldRow: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @Binding var tagNumber: String
    @Binding var tagColorID: UUID?

    @State private var showEditor = false

    private var selectedDef: TagColorDefinition? {
        tagColorLibrary.colors.first(where: { $0.id == tagColorID })
    }

    var body: some View {
        Button {
            showEditor = true
        } label: {
            HStack {
                Text("Tag")
                Spacer()

                if let def = selectedDef, !tagNumber.isEmpty {
                    AnimalTagView(
                        tagNumber: tagNumber,
                        color: def.color,
                        colorName: def.name
                    )
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEditor) {
            TagEditorView(
                tagNumber: $tagNumber,
                tagColorID: $tagColorID
            )
            .presentationDetents([.medium, .large])
        }
    }
}

struct TagEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @Binding var tagNumber: String
    @Binding var tagColorID: UUID?

    @State private var tempNumber: String = ""
    @State private var tempColorID: UUID?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        NavigationStack {
            Form {
                Section("Tag Number") {
                    TextField("Number", text: $tempNumber)
                        .keyboardType(.numberPad)
                        .font(.title2)
                }

                Section("Color") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(tagColorLibrary.colors) { def in
                            let isSelected = def.id == tempColorID

                            Circle()
                                .fill(def.color)
                                .frame(height: 44)
                                .overlay {
                                    if isSelected {
                                        Circle()
                                            .strokeBorder(.primary, lineWidth: 3)
                                    }
                                }
                                .onTapGesture {
                                    tempColorID = def.id
                                }
                        }
                    }
                    .padding(.vertical, 4)

                    Button("Clear Color") {
                        tempColorID = nil
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Tag")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        tagNumber = tempNumber
                        tagColorID = tempColorID
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            tempNumber = tagNumber
            tempColorID = tagColorID
        }
    }
}

struct DistinguishingFeaturesSection: View {
    @Binding var features: [DistinguishingFeature]

    var body: some View {
        Section("Distinguishing Features") {
            if features.isEmpty {
                Text("No distinguishing features")
                    .foregroundStyle(.secondary)
            }

            ForEach($features) { $feature in
                TextField("Feature", text: $feature.description)
            }
            .onDelete { offsets in
                features.remove(atOffsets: offsets)
            }

            Button("Add Feature") {
                features.append(DistinguishingFeature(description: ""))
            }
        }
    }
}

struct ParentFieldRow: View {
    let title: String
    @Binding var value: String
    let type: ParentPickerType
    @Binding var activePicker: ParentPickerType?

    var body: some View {
        Button {
            activePicker = type
        } label: {
            HStack {
                Text(title)
                Spacer()

                if value.isEmpty {
                    Text("—")
                        .foregroundStyle(.secondary)
                } else {
                    Text(value)
                        .foregroundStyle(.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AnimalFormView: View {
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @Binding var name: String
    @Binding var tagNumber: String
    @Binding var tagColorID: UUID?
    @Binding var sex: Sex
    @Binding var birthDate: Date
    @Binding var status: AnimalStatus
    @Binding var pasture: Pasture?
    @Binding var sire: String
    @Binding var dam: String
    @Binding var distinguishingFeatures: [DistinguishingFeature]

    let pastures: [Pasture]
    let excludeAnimal: Animal?
    let showsStatusPicker: Bool

    @Binding var activeParentPicker: ParentPickerType?

    init(
        name: Binding<String>,
        tagNumber: Binding<String>,
        tagColorID: Binding<UUID?>,
        sex: Binding<Sex>,
        birthDate: Binding<Date>,
        status: Binding<AnimalStatus>,
        pasture: Binding<Pasture?>,
        sire: Binding<String>,
        dam: Binding<String>,
        distinguishingFeatures: Binding<[DistinguishingFeature]>,
        activeParentPicker: Binding<ParentPickerType?>,
        pastures: [Pasture],
        excludeAnimal: Animal? = nil,
        showsStatusPicker: Bool = true
    ) {
        self._name = name
        self._tagNumber = tagNumber
        self._tagColorID = tagColorID
        self._sex = sex
        self._birthDate = birthDate
        self._status = status
        self._pasture = pasture
        self._sire = sire
        self._dam = dam
        self._distinguishingFeatures = distinguishingFeatures
        self._activeParentPicker = activeParentPicker
        self.pastures = pastures
        self.excludeAnimal = excludeAnimal
        self.showsStatusPicker = showsStatusPicker
    }

    var body: some View {
        Group {
            Section("Details") {
                DatePicker("Birth Date", selection: $birthDate, displayedComponents: .date)

                Picker("Sex", selection: $sex) {
                    ForEach(Sex.allCases, id: \.self) { sex in
                        Text(sex.label).tag(sex)
                    }
                }

                Picker("Pasture", selection: $pasture) {
                    Text("None").tag(Pasture?.none)

                    ForEach(pastures) { pasture in
                        Text(pasture.name)
                            .tag(Optional(pasture))
                    }
                }

                if showsStatusPicker {
                    Picker("Status", selection: $status) {
                        ForEach(AnimalStatus.allCases, id: \.self) { status in
                            Label(status.label, systemImage: status.systemImage)
                                .tag(status)
                        }
                    }
                }
            }

            Section("Parents") {
                ParentFieldRow(
                    title: "Dam",
                    value: $dam,
                    type: .dam,
                    activePicker: $activeParentPicker
                )

                if !dam.isEmpty {
                    Button("Clear Dam") { dam = "" }
                        .foregroundStyle(.secondary)
                }

                ParentFieldRow(
                    title: "Sire",
                    value: $sire,
                    type: .sire,
                    activePicker: $activeParentPicker
                )

                if !sire.isEmpty {
                    Button("Clear Sire") { sire = "" }
                        .foregroundStyle(.secondary)
                }
            }

            Section("Identification") {
                TagFieldRow(
                    tagNumber: $tagNumber,
                    tagColorID: $tagColorID
                )

                TextField("Name", text: $name)
            }

            DistinguishingFeaturesSection(features: $distinguishingFeatures)
        }
    }
}
