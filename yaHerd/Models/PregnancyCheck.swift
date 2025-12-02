//
//  PregnancyCheck.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//


import SwiftData
import Foundation

@Model
final class PregnancyCheck {
    var date: Date
    var result: PregnancyResult
    var technician: String?

    @Relationship(inverse: \Animal.pregnancyChecks) var animal: Animal

    init(date: Date, result: PregnancyResult, technician: String? = nil, animal: Animal) {
        self.date = date
        self.result = result
        self.technician = technician
        self.animal = animal
    }
}

enum PregnancyResult: String, Codable, CaseIterable {
    case open
    case pregnant
    case unknown
}
