import Foundation

struct PastureGroupInput: Hashable {
    var name: String
    var grazeDays: Int
    var restDays: Int

    var normalized: PastureGroupInput {
        PastureGroupInput(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            grazeDays: grazeDays,
            restDays: restDays
        )
    }
}
