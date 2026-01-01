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
    @Bindable var pasture: Pasture
    @AppStorage("targetHeadPerAcreDefault") private var targetHeadPerAcreDefault = 1.0
    @AppStorage("usableAcreagePercentDefault") private var usableAcreagePercentDefault = 100
    @Query(sort: \PastureGroup.name) private var groups: [PastureGroup]

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
                    value.wrappedValue = parsed
                } else {
                    value.wrappedValue = nil
                }
            }
        )
    }


    var body: some View {
        Form {
            Section("Pasture Info") {
                Text("Name: \(pasture.name)")

                if let acres = pasture.acreage {
                    Text("Acreage: \(acres, format: .number)")
                }

                if let usable = pasture.usableAcreage {
                    Text("Usable Acres: \(usable, format: .number)")
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
                            TagColorDot(tagColor: animal.tagColor ?? .yellow)
                            Text("Tag \(animal.tagNumber)")
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
        .navigationDestination(for: Animal.self) { animal in
            AnimalDetailView(animal: animal)
        }
    }
}

