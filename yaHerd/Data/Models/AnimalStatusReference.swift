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
    @Attribute(.unique) var id: UUID
    var name: String
    var baseStatus: AnimalStatus
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        baseStatus: AnimalStatus,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.baseStatus = baseStatus
        self.createdAt = createdAt
    }
}
