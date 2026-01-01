//
//  GrazingRotationService.swift
//  yaHerd
//
//  Created by mm on 12/14/25.
//


import Foundation

struct GrazingRotationService {

    static func isPastureRested(_ pasture: Pasture, asOf date: Date = .now) -> Bool {
        guard
            let group = pasture.group,
            let lastGrazed = pasture.lastGrazedDate
        else { return true }

        let days = Calendar.current.dateComponents(
            [.day],
            from: lastGrazed,
            to: date
        ).day ?? 0

        return days >= group.restDays
    }

    static func nextAvailablePastures(
        in group: PastureGroup,
        asOf date: Date = .now
    ) -> [Pasture] {
        group.pastures
            .filter { isPastureRested($0, asOf: date) }
            .sorted {
                ($0.lastGrazedDate ?? .distantPast)
                < ($1.lastGrazedDate ?? .distantPast)
            }
    }
}
