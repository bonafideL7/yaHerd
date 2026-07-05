//
//  WorkingProtocolTemplate.swift
//  yaHerd
//

import SwiftData
import Foundation

@Model
final class WorkingProtocolTemplate {
    var publicID: UUID = UUID()
    @Relationship(deleteRule: .nullify) var herd: Herd?
    var name: String = ""
    var items: [WorkingProtocolItem] = []

    init(publicID: UUID = UUID(), name: String, items: [WorkingProtocolItem]) {
        self.publicID = publicID
        self.name = name
        self.items = items
    }
}
