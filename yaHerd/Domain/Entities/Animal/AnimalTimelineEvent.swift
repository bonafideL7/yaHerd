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
    let id: String
    let date: Date
    let type: AnimalTimelineEventType
    let title: String
    let details: String?

    init(id: String, date: Date, type: AnimalTimelineEventType, title: String, details: String?) {
        self.id = id
        self.date = date
        self.type = type
        self.title = title
        self.details = details
    }
}
