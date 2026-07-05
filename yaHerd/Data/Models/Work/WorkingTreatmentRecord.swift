//
//  WorkingTreatmentRecord.swift
//  yaHerd
//

import SwiftData
import Foundation

/// Stores per-animal protocol completion for a working session.
@Model
final class WorkingTreatmentRecord {
    var publicID: UUID = UUID()
    @Relationship(deleteRule: .nullify) var herd: Herd?
    var date: Date = Date.now
    var itemName: String = ""
    var given: Bool = false
    var quantity: Double?

    @Relationship(deleteRule: .nullify)
    var animal: Animal?

    @Relationship(deleteRule: .nullify)
    var session: WorkingSession?

    init(
        publicID: UUID = UUID(),
        date: Date = Date.now,
        itemName: String,
        given: Bool,
        quantity: Double? = nil,
        animal: Animal,
        session: WorkingSession
    ) {
        self.publicID = publicID
        self.date = date
        self.itemName = itemName
        self.given = given
        self.quantity = quantity
        self.animal = animal
        self.session = session
    }
}
