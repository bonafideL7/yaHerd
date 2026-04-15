//
//  AnimalTimelineContainerView.swift
//

import SwiftUI

struct AnimalTimelineContainerView: View {
    @EnvironmentObject private var dependencies: AppDependencies

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
            events = (try? dependencies.animalRepository.fetchTimeline(id: animalID)) ?? []
            hasLoaded = true
        }
    }
}
