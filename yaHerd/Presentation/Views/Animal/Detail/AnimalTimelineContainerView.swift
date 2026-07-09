//
//  AnimalTimelineContainerView.swift
//

import SwiftUI

struct AnimalTimelineContainerView: View {
    @Environment(\.animalTimelineReader) private var timelineReader

    let animalID: UUID

    @State private var events: [AnimalTimelineEvent] = []
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if hasLoaded {
                if let errorMessage {
                    ContentUnavailableView(
                        "Timeline Unavailable",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(errorMessage)
                    )
                } else if events.isEmpty {
                    ContentUnavailableView("Timeline Unavailable", systemImage: "clock.arrow.circlepath")
                } else {
                    AnimalTimelineView(events: events)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            guard !hasLoaded else { return }
            do {
                events = try timelineReader.fetchTimeline(id: animalID)
                errorMessage = nil
            } catch {
                events = []
                errorMessage = UserVisibleErrorMessage.make(error)
            }
            hasLoaded = true
        }
    }
}
