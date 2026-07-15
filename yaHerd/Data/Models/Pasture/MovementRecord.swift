//
//  MovementRecord.swift
//  yaHerd
//
//  Created by mm on 12/1/25.
//


import SwiftData
import Foundation

extension YaHerdSchemaV1 {
    @Model
    final class MovementRecord {
        var publicID: UUID = UUID()
        @Relationship(deleteRule: .nullify) var herd: Herd?
        var date: Date = Date.now
        var fromPasture: String?
        var toPasture: String?

        @Relationship(deleteRule: .nullify) var animal: Animal?

        init(
            publicID: UUID = UUID(),
            date: Date,
            fromPasture: String?,
            toPasture: String?,
            animal: Animal
        ) {
            self.publicID = publicID
            self.date = date
            self.fromPasture = fromPasture
            self.toPasture = toPasture
            self.animal = animal
        }
    }
}
