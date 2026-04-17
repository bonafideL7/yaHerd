import Foundation

enum AnimalTimelineEventType {
    case birth
    case health
    case pregnancy
    case movement
    case status
    case tag
}

struct AnimalTimelineEvent: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let type: AnimalTimelineEventType
    let title: String
    let details: String?
    let icon: String

    init(id: UUID = UUID(), date: Date, type: AnimalTimelineEventType, title: String, details: String?, icon: String) {
        self.id = id
        self.date = date
        self.type = type
        self.title = title
        self.details = details
        self.icon = icon
    }
}
