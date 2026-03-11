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

    let pastures: [Pasture]
    let excludeAnimal: Animal?

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
        activeParentPicker: Binding<ParentPickerType?>,
        pastures: [Pasture],
        excludeAnimal: Animal? = nil
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
        self._activeParentPicker = activeParentPicker
        self.pastures = pastures
        self.excludeAnimal = excludeAnimal
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
                
                Picker("Status", selection: $status) {
                    ForEach(AnimalStatus.allCases, id: \.self) { status in
                        Text(status.rawValue.capitalized).tag(status)
                    }
                }
                
                Picker("Pasture", selection: $pasture) {
                    Text("None").tag(Pasture?.none)
                    
                    ForEach(pastures) { pasture in
                        Text(pasture.name)
                            .tag(Optional(pasture))
                    }
                }
            }
            
            Section("Parents") {
                HStack {
                    TextField("Dam", text: $dam)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Pick") { activeParentPicker = .dam }
                }
                
                if !dam.isEmpty {
                    Button("Clear Dam") { dam = "" }
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    TextField("Sire", text: $sire)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Pick") { activeParentPicker = .sire }
                }
                
                if !sire.isEmpty {
                    Button("Clear Sire") { sire = "" }
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Identification") {
                TextField("Tag Number", text: $tagNumber)
                
                Picker("Tag Color", selection: $tagColorID) {
                    Text("None").tag(UUID?.none)
                    
                    ForEach(tagColorLibrary.colors) { def in
                        HStack(spacing: 10) {
                            TagColorTagIcon(color: def.color, accessibilityLabel: "Tag color: \(def.name)")
                            Text("\(def.name) (\(def.prefix))")
                        }
                        .tag(Optional(def.id))
                    }
                }
                
                TextField("Name", text: $name)
            }
        }        
    }
}
