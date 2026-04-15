//
//  WorkingProtocolTemplate.swift
//  yaHerd
//

import SwiftData
import Foundation

@Model
final class WorkingProtocolTemplate {
    @Attribute(.unique) var publicID: UUID
    @Attribute(.unique)
    var name: String
    var items: [WorkingProtocolItem]

    init(publicID: UUID = UUID(), name: String, items: [WorkingProtocolItem]) {
        self.publicID = publicID
        self.name = name
        self.items = items
    }
}
