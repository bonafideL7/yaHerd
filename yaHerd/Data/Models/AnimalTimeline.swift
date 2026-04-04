//
//  AnimalTimeline.swift
//  yaHerd
//
//  Created by mm on 12/1/25.
//


import Foundation
import LucideIcons

enum AnimalTimelineEventType {
    case health
    case pregnancy
    case movement
    case status
    case tag
}

struct AnimalTimelineEvent: Identifiable {
    let id = UUID()
    let date: Date
    let type: AnimalTimelineEventType
    let title: String
    let details: String?
    let icon: String
}

// MARK: - Timeline Construction
extension Animal {
    var timelineEvents: [AnimalTimelineEvent] {
        var events: [AnimalTimelineEvent] = []

        // HEALTH RECORDS
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

        // PREGNANCY CHECKS
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

        // MOVEMENT HISTORY
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

        // STATUS HISTORY
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

        // TAG HISTORY
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

        // Sort newest → oldest
        return events.sorted { $0.date > $1.date }
    }
}
