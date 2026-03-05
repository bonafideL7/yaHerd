//
//  HealthRecord.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//


import SwiftData
import Foundation

@Model
final class HealthRecord {
    var date: Date
    var treatment: String
    var notes: String?

    @Relationship(deleteRule: .nullify) var workingSession: WorkingSession?
    @Relationship(inverse: \Animal.healthRecords) var animal: Animal

    init(
        date: Date,
        treatment: String,
        notes: String? = nil,
        workingSession: WorkingSession? = nil,
        animal: Animal
    ) {
        self.date = date
        self.treatment = treatment
        self.notes = notes
        self.workingSession = workingSession
        self.animal = animal
    }
}

