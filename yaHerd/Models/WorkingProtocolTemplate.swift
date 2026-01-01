//
//  WorkingProtocolTemplate.swift
//  yaHerd
//

import SwiftData
import Foundation

@Model
final class WorkingProtocolTemplate {
    @Attribute(.unique)
    var name: String
    var items: [WorkingProtocolItem]

    init(name: String, items: [WorkingProtocolItem]) {
        self.name = name
        self.items = items
    }
}
