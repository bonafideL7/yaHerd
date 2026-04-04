//
//  PastureDetailView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct PastureDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore
    @Bindable var pasture: Pasture
    @AppStorage("targetAcresPerHeadDefault") private var targetAcresPerHeadDefault = 3.0
    @AppStorage("usableAcreagePercentDefault") private var usableAcreagePercentDefault = 100
    @Query(sort: \PastureGroup.name) private var groups: [PastureGroup]
    @Query(sort: \Pasture.name) private var allPastures: [Pasture]
    
    @State private var isEditing = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    @State private var originalName: String = ""
    @State private var originalAcreage: Double? = nil
    @State private var originalUsableAcreage: Double? = nil
    @State private var originalTargetAcresPerHead: Double? = nil
    @State private var acreageText: String = ""
    @State private var usableAcreageText: String = ""
    @State private var targetHeadAcreageText: String = ""
    
    //    @State private var originalLastGrazedDate: Date? = nil
    
    private var analytics: PastureAnalytics {
        PastureAnalytics(
            pasture: pasture,
            aliveAnimals: pasture.animals.filter { $0.isActiveInHerd }.count
        )
    }
    
    //    private func nonOptionalDateBinding(for value: Binding<Date?>, fallback: Date = Date()) -> Binding<Date> {
    //        Binding<Date>(
    //            get: { value.wrappedValue ?? fallback },
    //            set: { value.wrappedValue = $0 }
    //        )
    //    }
    
    private func beginEditing() {
        originalName = pasture.name
        originalAcreage = pasture.acreage
        originalUsableAcreage = pasture.usableAcreage
        originalTargetAcresPerHead = pasture.targetAcresPerHead
        acreageText = pasture.acreage.map { String($0) } ?? ""
        usableAcreageText = pasture.usableAcreage.map { String($0) } ?? ""
        targetHeadAcreageText = pasture.targetAcresPerHead.map { String($0) } ?? ""
        //        originalLastGrazedDate = pasture.lastGrazedDate
        isEditing = true
    }
    
    private func cancelEditing() {
        pasture.name = originalName
        pasture.acreage = originalAcreage
        pasture.usableAcreage = originalUsableAcreage
        pasture.targetAcresPerHead = originalTargetAcresPerHead
        //        pasture.lastGrazedDate = originalLastGrazedDate
        isEditing = false
        try? context.save()
    }
    
    private func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "." {
            return nil
        }
        if trimmed.hasSuffix(".") {
            return Double(trimmed.dropLast())
        }
        return Double(trimmed)
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
        
        pasture.acreage = parseDouble(acreageText)
        pasture.usableAcreage = parseDouble(usableAcreageText)
        pasture.targetAcresPerHead = parseDouble(targetHeadAcreageText)
        
        do {
            try context.save()
            isEditing = false
        } catch {
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
                        TextField("acres", text: $acreageText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                    
                    //                    HStack {
                    //                        Text("Last Grazed")
                    //                        Spacer()
                    //                        if pasture.lastGrazedDate == nil {
                    //                            Button("Set") { pasture.lastGrazedDate = Date() }
                    //                        } else {
                    //                            DatePicker(
                    //                                "",
                    //                                selection: nonOptionalDateBinding(for: $pasture.lastGrazedDate),
                    //                                displayedComponents: [.date]
                    //                            )
                    //                            .labelsHidden()
                    //
                    //                            Button("Clear") { pasture.lastGrazedDate = nil }
                    //                                .foregroundStyle(.red)
                    //                        }
                    //                    }
                } else {
                    Text("Active Animals: \(analytics.activeAnimals)")
                    HStack{
                        if let acres = pasture.acreage {
                            Text("Acreage: \(acres, format: .number)")
                        }
                        Spacer()
                        if let usable = pasture.usableAcreage, usable != pasture.acreage {
                            Text("Usable Acres: \(usable, format: .number)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    //                    if let last = pasture.lastGrazedDate {
                    //                        Text("Last Grazed: \(last.formatted(date: .abbreviated, time: .omitted))")
                    //                    }
                }
            }
            
            Section("Stocking") {
                if isEditing {
                    HStack {
                        Text("Usable Acres")
                        Spacer()
                        TextField("usableAcres", text: $usableAcreageText)
                            .keyboardType(.decimalPad)
                    }
                    
                    HStack {
                        Text("Target Acres/Head")
                        Spacer()
                        TextField("rate", text: $targetHeadAcreageText)
                            .keyboardType(.decimalPad)
                    }
                    
                    //                    Button("Apply Defaults") {
                    //                        if let acres = pasture.acreage {
                    //                            pasture.usableAcreage = acres * (Double(usableAcreagePercentDefault) / 100)
                    //                        }
                    //                        pasture.targetAcresPerHead = targetAcresPerHeadDefault
                    //                        try? context.save()
                    //                    }
                } else {
                    
                    if let cap = analytics.capacityHead {
                        Text("Capacity: \(cap, format: .number.precision(.fractionLength(2)))")
                    }
                    
                    Text("Stocking Rate: \(analytics.acresPerHead, format: .number.precision(.fractionLength(2))) acres/head")
                    
                    if let target = analytics.targetAcresPerHead {
                        Text("Target Rate: \(target, format: .number.precision(.fractionLength(2))) acres/head")
                    }
                    
                    
                    HStack{
                        if let util = analytics.utilizationPercent {
                            Text("Utilization: \(util, format: .percent.precision(.fractionLength(2)))")
                                .foregroundStyle(util > 0.9 ? .red : util > 0.75 ? .orange : .green)
                        }
                        Spacer()
                        if analytics.isOverstocked {
                            Label("Overstocked", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        } else if analytics.isUnderutilized {
                            Label("Underutilized", systemImage: "arrow.down.left.and.arrow.up.right")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            
            let aliveAnimals = pasture.animals.filter { $0.isActiveInHerd }
            
            if !aliveAnimals.isEmpty {
                Section("Animals") {
                    ForEach(aliveAnimals) { animal in
                        NavigationLink(value: animal) {
                            let def = tagColorLibrary.resolvedDefinition(for: animal)
                            
                            AnimalTagView(
                                tagNumber: animal.tagNumber,
                                color: def.color,
                                colorName: def.name
                            )
                        }
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
