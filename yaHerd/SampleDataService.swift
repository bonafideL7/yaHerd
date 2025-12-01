//
//  SampleDataService.swift
//  yaHerd
//
//  Created by mm on 11/30/25.
//


import SwiftData
import Foundation

struct SampleDataService {

    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Animal>()
        let existing = try? context.fetch(descriptor)

        // If animals exist, don't seed again.
        if let existing, !existing.isEmpty { return }

        // Pastures
        let north = Pasture(name: "North Pasture", acreage: 35)
        let south = Pasture(name: "South Pasture", acreage: 28)
        let drylot = Pasture(name: "Drylot", acreage: 5)

        context.insert(north)
        context.insert(south)
        context.insert(drylot)

        // Animals
        let a1 = Animal(tagNumber: "101", sex: .cow, birthDate: Date().addingTimeInterval(-3_000_000), status: .alive, sire: "A13", dam: "B07", pasture: north)
        let a2 = Animal(tagNumber: "102", sex: .cow, birthDate: Date().addingTimeInterval(-2_700_000), status: .alive, sire: "A13", dam: "B07", pasture: south)
        let a3 = Animal(tagNumber: "201", sex: .bull, birthDate: Date().addingTimeInterval(-4_200_000), status: .alive, sire: "X99", dam: "C21", pasture: drylot)
        let a4 = Animal(tagNumber: "301", sex: .heifer, birthDate: Date().addingTimeInterval(-1_000_000), status: .alive, sire: "A55", dam: "C33", pasture: north)

        context.insert(a1)
        context.insert(a2)
        context.insert(a3)
        context.insert(a4)

        // Sample health and preg checks
        context.insert(HealthRecord(date: .now, treatment: "Vaccination", notes: "Initial shot", animal: a1))
        context.insert(HealthRecord(date: .now, treatment: "Deworming", notes: nil, animal: a3))

        context.insert(PregnancyCheck(date: .now, result: .pregnant, technician: "Dr Smith", animal: a1))
        context.insert(PregnancyCheck(date: .now, result: .open, technician: "Dr Smith", animal: a2))
    }
}
