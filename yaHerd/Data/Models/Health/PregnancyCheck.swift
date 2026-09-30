//
//  PregnancyCheck.swift
//  yaHerd
//
//  Created by mm on 11/28/25.
//


import SwiftData
import Foundation

extension YaHerdSchemaV1 {
    @Model
    final class PregnancyCheck {
        var publicID: UUID = UUID()
        @Relationship(deleteRule: .nullify) var herd: Herd?
        var date: Date = Date.now
        var result: PregnancyResult = PregnancyResult.unknown
        var technician: String?

        /// Optional estimated days pregnant (if known).
        var estimatedDaysPregnant: Int?
        /// Optional due date. If `estimatedDaysPregnant` is provided, this can be auto-calculated.
        var dueDate: Date?

        /// Optional breeding sire for this pregnancy.
        @Relationship(deleteRule: .nullify)
        var sireAnimal: Animal?

        /// Optional link to a working session that captured this check.
        @Relationship(deleteRule: .nullify)
        var workingSession: WorkingSession?

        @Relationship(deleteRule: .nullify) var animal: Animal?

        init(
            publicID: UUID = UUID(),
            date: Date,
            result: PregnancyResult,
            technician: String? = nil,
            estimatedDaysPregnant: Int? = nil,
            dueDate: Date? = nil,
            sireAnimal: Animal? = nil,
            workingSession: WorkingSession? = nil,
            animal: Animal
        ) {
            self.publicID = publicID
            self.date = date
            self.result = result
            self.technician = technician
            self.estimatedDaysPregnant = estimatedDaysPregnant
            self.dueDate = dueDate
            self.sireAnimal = sireAnimal
            self.workingSession = workingSession
            self.animal = animal
        }
    }
}

enum PregnancyResult: String, Codable, CaseIterable {
    case open
    case pregnant
    case unknown
}
