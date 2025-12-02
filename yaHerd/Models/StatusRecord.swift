//
//  StatusRecord.swift
//  yaHerd
//
//  Created by mm on 12/1/25.
//


import SwiftData
import Foundation

@Model
final class StatusRecord {
    var date: Date
    var oldStatus: AnimalStatus
    var newStatus: AnimalStatus

    @Relationship var animal: Animal

    init(date: Date, oldStatus: AnimalStatus, newStatus: AnimalStatus, animal: Animal) {
        self.date = date
        self.oldStatus = oldStatus
        self.newStatus = newStatus
        self.animal = animal
    }
}
