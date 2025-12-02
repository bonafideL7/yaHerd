//
//  MovementRecord.swift
//  yaHerd
//
//  Created by mm on 12/1/25.
//


import SwiftData
import Foundation

@Model
final class MovementRecord {
    var date: Date
    var fromPasture: String?
    var toPasture: String?

    @Relationship(inverse: \Animal.movementRecords) var animal: Animal

    init(date: Date, fromPasture: String?, toPasture: String?, animal: Animal) {
        self.date = date
        self.fromPasture = fromPasture
        self.toPasture = toPasture
        self.animal = animal
    }
}
