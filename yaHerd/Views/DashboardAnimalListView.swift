//
//  DashboardAnimalListView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

/// Lightweight, read-only animal list used for dashboard drill-downs.
struct DashboardAnimalListView: View {

    @EnvironmentObject private var tagColorLibrary: TagColorLibraryStore

    @AppStorage("pregCheckIntervalDays") private var pregCheckIntervalDays = 180
    @AppStorage("treatmentIntervalDays") private var treatmentIntervalDays = 180

    @Query private var animals: [Animal]

    let kind: DashboardAnimalListKind

    private var filtered: [Animal] {
        let now = Date()

        let base: [Animal] = {
            switch kind {
            case .alive:
                return animals.filter { $0.status == .alive }
            case .workingPen:
                return animals.filter { $0.status == .alive && $0.location == .workingPen }
            case .unassigned:
                return animals.filter { $0.status == .alive && $0.location == .pasture && $0.pasture == nil }
            case .overduePregChecks:
                return animals.filter { animal in
                    guard animal.status == .alive else { return false }
                    guard let last = animal.pregnancyChecks.sorted(by: { $0.date > $1.date }).first else { return false }
                    let days = Calendar.current.dateComponents([.day], from: last.date, to: now).day ?? 0
                    return days > pregCheckIntervalDays
                }
            case .overdueTreatments:
                // Keep this aligned with DashboardService (does not filter by status).
                return animals.filter { animal in
                    guard let last = animal.healthRecords.sorted(by: { $0.date > $1.date }).first else { return false }
                    let days = Calendar.current.dateComponents([.day], from: last.date, to: now).day ?? 0
                    return days > treatmentIntervalDays
                }
            }
        }()

        return base.sorted { $0.tagNumber.localizedStandardCompare($1.tagNumber) == .orderedAscending }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                Text("Nothing to show.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filtered) { animal in
                    NavigationLink(value: animal) {
                        row(animal)
                    }
                }
            }
        }
        .navigationTitle(kind.title)
    }

    private func row(_ animal: Animal) -> some View {
        HStack(spacing: 12) {
            let def = tagColorLibrary.resolvedDefinition(for: animal)
            TagColorTagIcon(color: def.color, accessibilityLabel: "Tag color: \(def.name)")

            VStack(alignment: .leading, spacing: 2) {
                Text(tagColorLibrary.formattedTag(for: animal))
                    .font(.headline)

                HStack(spacing: 6) {
                    Text((animal.biologicalSex ?? .female).label)
                    if animal.location == .workingPen {
                        Text("• Working Pen")
                    } else if let pasture = animal.pasture?.name {
                        Text("• \(pasture)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
