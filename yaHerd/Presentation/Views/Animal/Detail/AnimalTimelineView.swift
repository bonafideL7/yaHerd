//
//  AnimalTimelineView.swift
//  yaHerd
//
//  Created by mm on 12/1/25.
//


import SwiftUI
import LucideIcons

struct AnimalTimelineView: View {
    let events: [AnimalTimelineEvent]
    
    private var grouped: [String: [String: [AnimalTimelineEvent]]] {
        Dictionary(
            grouping: events,
            by: { $0.date.formatted(.dateTime.year()) }
        ).mapValues { yearGroup in
            Dictionary(
                grouping: yearGroup,
                by: { $0.date.formatted(.dateTime.year().month()) }
            )
        }
    }

    var body: some View {
        List {
            ForEach(grouped.keys.sorted(by: >), id: \.self) { year in
                Section(year) {
                    let months = (grouped[year]?.keys.sorted(by: >)) ?? []

                    ForEach(months, id: \.self) { month in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(month)
                                .font(.headline)
                                .padding(.top, 4)

                            ForEach(mergedByDay(grouped[year]?[month] ?? [])) { dayGroup in
                                VStack(alignment: .leading) {
                                    Text(dayGroup.dateString)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    ForEach(dayGroup.events) { event in
                                        timelineRow(event)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Timeline")
    }

    private func timelineRow(_ event: AnimalTimelineEvent) -> some View {
        HStack(alignment: .top) {
            if let icon = UIImage(lucideId: event.icon) {
                Image(uiImage: icon.scaled(to: CGSize(width: 20, height: 20)))
                    .renderingMode(.template)
                    .foregroundStyle(color(for: event.type))
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.headline)

                if let details = event.details {
                    Text(details)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
    }

    private func mergedByDay(_ events: [AnimalTimelineEvent])
        -> [DayGroup]
    {
        let groups = Dictionary(
            grouping: events,
            by: { Calendar.current.startOfDay(for: $0.date) }
        )

        return groups.map {
            DayGroup(date: $0.key, events: $0.value.sorted { $0.date > $1.date })
        }
        .sorted { $0.date > $1.date }
    }

    private func color(for type: AnimalTimelineEventType) -> Color {
        switch type {
        case .health: return .blue
        case .pregnancy: return .purple
        case .movement: return .green
        case .status: return .red
        case .tag: return .orange
        }
    }
}

struct DayGroup: Identifiable {
    let id = UUID()
    let date: Date
    let events: [AnimalTimelineEvent]

    var dateString: String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
