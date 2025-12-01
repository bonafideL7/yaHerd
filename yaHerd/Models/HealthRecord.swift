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

    @Relationship var animal: Animal

    init(date: Date, treatment: String, notes: String? = nil, animal: Animal) {
        self.date = date
        self.treatment = treatment
        self.notes = notes
        self.animal = animal
    }
}
