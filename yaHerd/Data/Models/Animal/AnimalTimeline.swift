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

        events.append(
            AnimalTimelineEvent(
                date: birthDate,
                type: .birth,
                title: "Birth",
                details: birthEventDetails,
                icon: "baby"
            )
        )

        for offspring in maternalOffspring where !offspring.isSoftDeleted {
            events.append(
                AnimalTimelineEvent(
                    date: offspring.birthDate,
                    type: .birth,
                    title: "Offspring Recorded",
                    details: offspringBirthEventDetails(for: offspring),
                    icon: "baby"
                )
            )
        }

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

        return events.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private var birthEventDetails: String? {
        let parentDetails = [
            formattedParentDetail(title: "Dam", animal: damAnimal),
            formattedParentDetail(title: "Sire", animal: sireAnimal)
        ]
        .compactMap { $0 }

        if let pastureName = pasture?.name, !pastureName.isEmpty {
            if parentDetails.isEmpty {
                return "Pasture: \(pastureName)"
            }
            return parentDetails.joined(separator: " • ") + " • Pasture: \(pastureName)"
        }

        return parentDetails.isEmpty ? nil : parentDetails.joined(separator: " • ")
    }

    private func offspringBirthEventDetails(for offspring: Animal) -> String? {
        var components: [String] = ["Offspring: \(offspring.displayTagNumber)"]

        if !offspring.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components.append("Name: \(offspring.name)")
        }

        if let sireDisplay = offspring.sireAnimal?.displayTagNumber, !sireDisplay.isEmpty {
            components.append("Sire: \(sireDisplay)")
        }

        return components.joined(separator: " • ")
    }

    private func formattedParentDetail(title: String, animal: Animal?) -> String? {
        guard let animal else { return nil }
        let display = animal.displayTagNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !display.isEmpty else { return nil }
        return "\(title): \(display)"
    }
}
