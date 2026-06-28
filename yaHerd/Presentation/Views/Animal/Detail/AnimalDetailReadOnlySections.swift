//
//  AnimalDetailReadOnlySections.swift
//

import SwiftUI

struct AnimalDetailOverviewSection: View {
    let detail: AnimalDetailSnapshot

    var body: some View {
        Section("Overview") {
            if !detail.name.isEmpty {
                LabeledContent("Name") {
                    Text(detail.name.nilIfEmpty ?? "—")
                }
            }

            LabeledContent("Birth Date") {
                Text(detail.birthDate.formatted(date: .abbreviated, time: .omitted))
            }

            LabeledContent("Sex") {
                Text(detail.sex.label)
            }

            LabeledContent("Pasture") {
                Text(detail.pastureName ?? "None")
            }
        }
    }
}

struct AnimalDetailLineageSection: View {
    @Binding var isExpanded: Bool
    let detail: AnimalDetailSnapshot

    var body: some View {
        let dam = detail.dam?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sire = detail.sire?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDam = !(dam ?? "").isEmpty
        let hasSire = !(sire ?? "").isEmpty

        if hasDam || hasSire {
            Section {
                DisclosureGroup("Parents", isExpanded: $isExpanded) {
                    if let dam, !dam.isEmpty {
                        LabeledContent("Dam") { Text(dam) }
                    }
                    if let sire, !sire.isEmpty {
                        LabeledContent("Sire") { Text(sire) }
                    }
                }
            }
        }
    }
}

struct AnimalDetailDistinguishingFeaturesSection: View {
    let detail: AnimalDetailSnapshot

    var body: some View {
        if !detail.distinguishingFeatures.isEmpty {
            Section("Distinguishing Features") {
                ForEach(detail.distinguishingFeatures.orderedDistinguishingFeatures) { feature in
                    Text(feature.description)
                }
            }
        }
    }
}

struct AnimalDetailOffspringSection: View {
    let detail: AnimalDetailSnapshot
    let canAddOffspring: Bool
    let onAddOffspring: () -> Void

    var body: some View {
        if detail.sex == .female {
            Section {
                if !detail.maternalOffspring.isEmpty {
                    ForEach(detail.maternalOffspring) { offspring in
                        NavigationLink(value: offspring.id) {
                            AnimalListRowContent(animal: offspring)
                        }
                    }
                }

                if canAddOffspring {
                    Button {
                        onAddOffspring()
                    } label: {
                        HStack {
                            Text("Add Offspring")
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }

                if detail.maternalOffspring.isEmpty {
                    Text("No offspring recorded")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Offspring")
            }
        }
    }
}
