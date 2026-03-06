//
//  DashboardPastureListView.swift
//  yaHerd
//

import SwiftUI
import SwiftData

struct DashboardPastureListView: View {

    @Environment(\.modelContext) private var context

    @AppStorage("pastureCapacity") private var pastureCapacity = 30

    @Query(sort: \Pasture.name) private var pastures: [Pasture]

    @State private var filter: Filter = .all

    private var filteredPastures: [Pasture] {
        let cap = Double(pastureCapacity)
        switch filter {
        case .all:
            return pastures
        case .overstocked:
            return pastures.filter { p in
                let alive = p.animals.filter { $0.status == .alive }.count
                return PastureAnalytics(pasture: p, aliveAnimals: alive, fallbackCapacityHead: cap).isOverstocked
            }
        case .underutilized:
            return pastures.filter { p in
                let alive = p.animals.filter { $0.status == .alive }.count
                return PastureAnalytics(pasture: p, aliveAnimals: alive, fallbackCapacityHead: cap).isUnderutilized
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Pastures", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if filteredPastures.isEmpty {
                    Text("No matching pastures.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredPastures) { pasture in
                        NavigationLink(value: pasture) {
                            pastureRow(pasture)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                pasture.lastGrazedDate = .now
                                try? context.save()
                            } label: {
                                Label("Grazed today", systemImage: "calendar")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle("Pastures")
    }

    private func pastureRow(_ pasture: Pasture) -> some View {
        let alive = pasture.animals.filter { $0.status == .alive }.count
        let analytics = PastureAnalytics(
            pasture: pasture,
            aliveAnimals: alive,
            fallbackCapacityHead: Double(pastureCapacity)
        )

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(pasture.name)
                    .font(.headline)

                Spacer()

                if analytics.isOverstocked {
                    Label("Over", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if analytics.isUnderutilized {
                    Label("Low", systemImage: "arrow.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Text("\(alive) head")
                if analytics.acres > 0 {
                    Text("• \(analytics.acres.formatted(.number.precision(.fractionLength(0...1)))) ac")
                }
                if let cap = analytics.capacityHead {
                    Text("• cap \(Int(cap))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let cap = analytics.capacityHead, cap > 0 {
                ProgressView(value: Double(alive), total: cap)
            }
        }
    }
}

private enum Filter: CaseIterable, Hashable {
    case all
    case overstocked
    case underutilized

    var label: String {
        switch self {
        case .all: return "All"
        case .overstocked: return "Over"
        case .underutilized: return "Low"
        }
    }
}
