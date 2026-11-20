import SwiftUI
import Observation

struct AnimalTimelineContainerView: View {
    @Environment(\.animalFeatureDependencies) private var animalDependencies
    private var timelineReader: any AnimalTimelineReading { animalDependencies.timelineReader }
    @Environment(AppCurrentHerdSelection.self) private var herdSelection
    @Environment(\.dismiss) private var dismiss

    let animalID: UUID
    let originatingHerdID: UUID
    let originatingSelectionRevision: UInt64

    @State private var model = AnimalTimelineContainerViewModel()

    private var isOriginCurrent: Bool {
        herdSelection.currentHerdID == originatingHerdID
            && herdSelection.selectionRevision == originatingSelectionRevision
    }

    var body: some View {
        Group {
            if !isOriginCurrent {
                ContentUnavailableView("Herd Changed", systemImage: "arrow.left.arrow.right")
            } else if model.hasCurrentEvents(
                for: herdSelection,
                originatingHerdID: originatingHerdID,
                originatingSelectionRevision: originatingSelectionRevision
            ) {
                if let errorMessage = model.errorMessage {
                    ContentUnavailableView(
                        "Timeline Unavailable",
                        systemImage: "clock.arrow.circlepath",
                        description: Text(errorMessage)
                    )
                } else if model.events.isEmpty {
                    ContentUnavailableView("Timeline Unavailable", systemImage: "clock.arrow.circlepath")
                } else {
                    AnimalTimelineView(events: model.events)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            guard isOriginCurrent else {
                dismiss()
                return
            }
            model.load(
                animalID: animalID,
                using: timelineReader,
                selection: herdSelection,
                originatingHerdID: originatingHerdID,
                originatingSelectionRevision: originatingSelectionRevision
            )
        }
        .onChange(of: herdSelection.selectionRevision) { _, _ in
            if !isOriginCurrent {
                dismiss()
            }
        }
        .profileBodyRecomputation("AnimalTimelineContainerView")
    }
}

@MainActor
@Observable
final class AnimalTimelineContainerViewModel {
    private(set) var events: [AnimalTimelineEvent] = []
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var loadedHerdID: UUID?
    @ObservationIgnored private var loadedSelectionRevision: UInt64?

    func hasCurrentEvents(
        for selection: AppCurrentHerdSelection,
        originatingHerdID: UUID,
        originatingSelectionRevision: UInt64
    ) -> Bool {
        hasLoaded
            && loadedHerdID == originatingHerdID
            && loadedSelectionRevision == originatingSelectionRevision
            && selection.currentHerdID == originatingHerdID
            && selection.selectionRevision == originatingSelectionRevision
    }

    func load(
        animalID: UUID,
        using reader: any AnimalTimelineReading,
        selection: AppCurrentHerdSelection,
        originatingHerdID: UUID,
        originatingSelectionRevision: UInt64
    ) {
        guard !hasLoaded,
              selection.currentHerdID == originatingHerdID,
              selection.selectionRevision == originatingSelectionRevision else { return }

        do {
            let loaded = try PerformanceLog.measure("AnimalTimeline.load") {
                try reader.fetchTimeline(id: animalID)
            }
            guard selection.currentHerdID == originatingHerdID,
                  selection.selectionRevision == originatingSelectionRevision else { return }
            events = loaded
            errorMessage = nil
        } catch {
            guard selection.currentHerdID == originatingHerdID,
                  selection.selectionRevision == originatingSelectionRevision else { return }
            events = []
            errorMessage = UserVisibleErrorMessage.make(error)
        }

        loadedHerdID = originatingHerdID
        loadedSelectionRevision = originatingSelectionRevision
        hasLoaded = true
    }
}
