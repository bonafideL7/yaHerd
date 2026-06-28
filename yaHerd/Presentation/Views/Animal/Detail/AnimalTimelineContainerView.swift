//
//  AnimalTimelineContainerView.swift
//

import SwiftUI

struct AnimalTimelineContainerView: View {
    @Environment(\.animalTimelineReader) private var timelineReader

    let animalID: UUID

    @State private var events: [AnimalTimelineEvent] = []
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if hasLoaded {
                if events.isEmpty {
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
            events = (try? timelineReader.fetchTimeline(id: animalID)) ?? []
            hasLoaded = true
        }
    }
}
