//
//  WorkingTreatmentRecord.swift
//  yaHerd
//

import SwiftData
import Foundation

/// Stores per-animal protocol completion for a working session.
@Model
final class WorkingTreatmentRecord {
    var date: Date
    var itemName: String
    var given: Bool
    var quantity: Double?

    @Relationship(deleteRule: .nullify)
    var animal: Animal?

    @Relationship(deleteRule: .nullify)
    var session: WorkingSession?

    init(
        date: Date = .now,
        itemName: String,
        given: Bool,
        quantity: Double? = nil,
        animal: Animal,
        session: WorkingSession
    ) {
        self.date = date
        self.itemName = itemName
        self.given = given
        self.quantity = quantity
        self.animal = animal
        self.session = session
    }
}
