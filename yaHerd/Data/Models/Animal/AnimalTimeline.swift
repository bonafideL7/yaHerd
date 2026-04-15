//
//  AnimalTimeline.swift
//  yaHerd
//
//  Created by mm on 12/1/25.
//

import Foundation

// MARK: - Timeline Construction
extension Animal {
    var timelineEvents: [AnimalTimelineEvent] {
        var events: [AnimalTimelineEvent] = []

        for r in healthRecords {
            events.append(
                AnimalTimelineEvent(
                    date: r.date,
                    type: .health,
                    title: r.treatment,
                    details: r.notes,
                    icon: "syringe"
                )
            )
        }

        for p in pregnancyChecks {
            events.append(
                AnimalTimelineEvent(
                    date: p.date,
                    type: .pregnancy,
                    title: "Pregnancy Check: \(p.result.rawValue.capitalized)",
                    details: p.technician,
                    icon: "baby"
                )
            )
        }

        for m in movementRecords {
            let desc = "\(m.fromPasture ?? "—") → \(m.toPasture ?? "—")"
            events.append(
                AnimalTimelineEvent(
                    date: m.date,
                    type: .movement,
                    title: "Pasture Movement",
                    details: desc,
                    icon: "move"
                )
            )
        }

        for s in statusRecords {
            let desc = "\(s.oldStatus.label) → \(s.newStatus.label)"
            events.append(
                AnimalTimelineEvent(
                    date: s.date,
                    type: .status,
                    title: "Status Change",
                    details: desc,
                    icon: "badge-alert"
                )
            )
        }

        for tag in tags {
            let details = tag.normalizedNumber
            events.append(
                AnimalTimelineEvent(
                    date: tag.assignedAt,
                    type: .tag,
                    title: "Tag Assigned",
                    details: details,
                    icon: "tag"
                )
            )

            if let removedAt = tag.removedAt {
                events.append(
                    AnimalTimelineEvent(
                        date: removedAt,
                        type: .tag,
                        title: "Tag Retired",
                        details: details,
                        icon: "tag"
                    )
                )
            }
        }

        return events.sorted { $0.date > $1.date }
    }
}
