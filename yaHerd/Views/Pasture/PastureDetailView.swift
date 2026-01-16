//
//  PastureDetailView.swift
//  yaHerd
//
//  Created by mm on 11/29/25.
//


import SwiftUI
import SwiftData

struct PastureDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Bindable var pasture: Pasture
    @AppStorage("targetHeadPerAcreDefault") private var targetHeadPerAcreDefault = 1.0
    @AppStorage("usableAcreagePercentDefault") private var usableAcreagePercentDefault = 100
    @Query(sort: \PastureGroup.name) private var groups: [PastureGroup]
    @Query(sort: \Pasture.name) private var allPastures: [Pasture]

    @State private var isEditing = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    @State private var originalName: String = ""
    @State private var originalAcreage: Double? = nil
    @State private var originalLastGrazedDate: Date? = nil

    private var analytics: PastureAnalytics {
        PastureAnalytics(
            pasture: pasture,
            aliveAnimals: pasture.animals.filter { $0.status == .alive }.count
        )
    }
    
    private func binding(for value: Binding<Double?>) -> Binding<String> {
        Binding<String>(
            get: {
                if let number = value.wrappedValue {
                    return String(number)
                } else {
                    return ""
                }
            },
            set: { newValue in
                if let parsed = Double(newValue) {
                    value.wrappedValue = parsed > 0 ? parsed : nil
                } else {
                    value.wrappedValue = nil
                }
            }
        )
    }

    private func nonOptionalDateBinding(for value: Binding<Date?>, fallback: Date = Date()) -> Binding<Date> {
        Binding<Date>(
            get: { value.wrappedValue ?? fallback },
            set: { value.wrappedValue = $0 }
        )
    }

    private func beginEditing() {
        originalName = pasture.name
        originalAcreage = pasture.acreage
        originalLastGrazedDate = pasture.lastGrazedDate
        isEditing = true
    }

    private func cancelEditing() {
        pasture.name = originalName
        pasture.acreage = originalAcreage
        pasture.lastGrazedDate = originalLastGrazedDate
        isEditing = false
        try? context.save()
    }

    private func saveEdits() {
        let trimmed = pasture.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            pasture.name = originalName
            alertMessage = "Pasture name can’t be empty."
            showAlert = true
            return
        }
        pasture.name = trimmed

        let duplicateExists = allPastures.contains { other in
            other !== pasture && other.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        if duplicateExists {
            pasture.name = originalName
            alertMessage = "A pasture named \(trimmed) already exists. Names must be unique."
            showAlert = true
            return
        }

        do {
            try context.save()
            isEditing = false
        } catch {
            // Restore the name if the unique constraint triggers in SwiftData.
            pasture.name = originalName
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }


    var body: some View {
        Form {
            Section("Pasture Info") {
                if isEditing {
                    TextField("Name", text: $pasture.name)

                    HStack {
                        Text("Acreage")
                        Spacer()
                        TextField("acres", text: binding(for: $pasture.acreage))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 120)
                    }

                    HStack {
                        Text("Last Grazed")
                        Spacer()
                        if pasture.lastGrazedDate == nil {
                            Button("Set") { pasture.lastGrazedDate = Date() }
                        } else {
                            DatePicker(
                                "",
                                selection: nonOptionalDateBinding(for: $pasture.lastGrazedDate),
                                displayedComponents: [.date]
                            )
                            .labelsHidden()

                            Button("Clear") { pasture.lastGrazedDate = nil }
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    Text("Name: \(pasture.name)")

                    if let acres = pasture.acreage {
                        Text("Acreage: \(acres, format: .number)")
                    }

                    if let usable = pasture.usableAcreage {
                        Text("Usable Acres: \(usable, format: .number)")
                    }

                    if let last = pasture.lastGrazedDate {
                        Text("Last Grazed: \(last.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
            }

            Section("Stocking") {
                Text("Alive Animals: \(analytics.aliveAnimals)")
                Text("Stocking Rate: \(analytics.headPerAcre, format: .number.precision(.fractionLength(2))) head/acre")

                if let target = analytics.targetHeadPerAcre {
                    Text("Target Rate: \(target, format: .number.precision(.fractionLength(2))) head/acre")
                }

                if let cap = analytics.capacityHead {
                    Text("Capacity: \(cap, format: .number)")
                }

                if let util = analytics.utilizationPercent {
                    Text("Utilization: \(util, format: .percent)")
                        .foregroundStyle(util > 0.9 ? .red : util > 0.75 ? .orange : .green)
                }

                if analytics.isOverstocked {
                    Label("Overstocked", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if analytics.isUnderutilized {
                    Label("Underutilized", systemImage: "arrow.down.left.and.arrow.up.right")
                        .foregroundStyle(.blue)
                }
            }
            
            Section("Stocking Settings") {

                // USABLE ACREAGE
                HStack {
                    Text("Usable Acres")
                    Spacer()
                    TextField("acres", text: binding(for: $pasture.usableAcreage))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                }

                // TARGET HEAD / ACRE
                HStack {
                    Text("Target Head/Acre")
                    Spacer()
                    TextField("rate", text: binding(for: $pasture.targetHeadPerAcre))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(width: 100)
                }

                Button("Apply Defaults") {
                    if let acres = pasture.acreage {
                        pasture.usableAcreage = acres * (Double(usableAcreagePercentDefault) / 100)
                    }
                    pasture.targetHeadPerAcre = targetHeadPerAcreDefault
                    try? context.save()
                }
            }

            Section("Animals") {
                ForEach(pasture.animals.filter { $0.status == .alive }) { animal in
                    NavigationLink(value: animal) {
                        HStack(spacing: 12) {
                            let def = tagColorLibrary.resolvedDefinition(for: animal)
                            TagColorTagIcon(color: def.color, accessibilityLabel: "Tag color: \(def.name)")
                            Text(tagColorLibrary.formattedTag(for: animal))
                        }
                    }
                }
            }
            
            Section("Rotation Group") {
                Picker("Group", selection: $pasture.group) {
                    Text("None").tag(Optional<PastureGroup>(nil))
                    ForEach(groups) { group in
                        Text(group.name).tag(Optional(group))
                    }
                }
            }

        }
        .navigationTitle(pasture.name)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveEdits() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancelEditing() }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { beginEditing() }
                }
            }
        }
        .alert("Can’t Save", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .navigationDestination(for: Animal.self) { animal in
            AnimalDetailView(animal: animal)
        }
    }
}

