//
//  AnimalStatusReference.swift
//  yaHerd
//
//  Created by OpenAI on 4/3/26.
//

import Foundation
import SwiftData

@Model
final class AnimalStatusReference {
    var id: UUID = UUID()
    var name: String = ""
    var baseStatus: AnimalStatus = AnimalStatus.active
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        baseStatus: AnimalStatus,
        createdAt: Date = Date.now
    ) {
        self.id = id
        self.name = name
        self.baseStatus = baseStatus
        self.createdAt = createdAt
    }
}
