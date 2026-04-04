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
    var oldStatusReferenceID: UUID?
    var newStatusReferenceID: UUID?

    @Relationship(inverse: \Animal.statusRecords) var animal: Animal

    init(
        date: Date,
        oldStatus: AnimalStatus,
        newStatus: AnimalStatus,
        oldStatusReferenceID: UUID? = nil,
        newStatusReferenceID: UUID? = nil,
        animal: Animal
    ) {
        self.date = date
        self.oldStatus = oldStatus
        self.newStatus = newStatus
        self.oldStatusReferenceID = oldStatusReferenceID
        self.newStatusReferenceID = newStatusReferenceID
        self.animal = animal
    }
}
