import Foundation
import XCTest
@testable import yaHerd

@MainActor
final class AnimalTimelineHerdIsolationTests: XCTestCase {
    func testLoadedTimelineIsNotExposedAfterHerdSwitchOrRoundTrip() {
        let originalHerdID = UUID()
        let otherHerdID = UUID()
        let animalID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let oldEvent = makeEvent("Old Herd")
        let otherEvent = makeEvent("Other Herd")
        let reader = TimelineHerdProbe(
            selection: selection,
            eventsByHerd: [originalHerdID: [oldEvent], otherHerdID: [otherEvent]]
        )
        let model = AnimalTimelineContainerViewModel()
        let revision = selection.selectionRevision

        model.load(
            animalID: animalID,
            using: reader,
            selection: selection,
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: revision
        )
        XCTAssertTrue(model.hasCurrentEvents(
            for: selection,
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: revision
        ))
        XCTAssertEqual(model.events, [oldEvent])

        selection.select(otherHerdID)
        XCTAssertFalse(model.hasCurrentEvents(
            for: selection,
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: revision
        ))
        model.load(
            animalID: animalID,
            using: reader,
            selection: selection,
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: revision
        )
        XCTAssertEqual(reader.fetchCount, 1, "An obsolete timeline must not query another Herd.")

        selection.select(originalHerdID)
        XCTAssertFalse(model.hasCurrentEvents(
            for: selection,
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: revision
        ), "Returning to the same UUID must not revive an earlier timeline.")

        let currentModel = AnimalTimelineContainerViewModel()
        let currentRevision = selection.selectionRevision
        currentModel.load(
            animalID: animalID,
            using: reader,
            selection: selection,
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: currentRevision
        )
        XCTAssertEqual(currentModel.events, [oldEvent])
        XCTAssertTrue(currentModel.hasCurrentEvents(
            for: selection,
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: currentRevision
        ))
        XCTAssertEqual(reader.fetchCount, 2)
    }

    func testDelayedTimelineDestinationNeverLoadsAgainstNewSelection() {
        let originalHerdID = UUID()
        let otherHerdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: originalHerdID)
        let revision = selection.selectionRevision
        let reader = TimelineHerdProbe(
            selection: selection,
            eventsByHerd: [otherHerdID: [makeEvent("Other Herd")]]
        )
        selection.select(otherHerdID)

        let model = AnimalTimelineContainerViewModel()
        model.load(
            animalID: UUID(),
            using: reader,
            selection: selection,
            originatingHerdID: originalHerdID,
            originatingSelectionRevision: revision
        )
        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.events.isEmpty)
        XCTAssertEqual(reader.fetchCount, 0)
    }

    func testUnavailableHerdNeverLoadsTimeline() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let reader = TimelineHerdProbe(selection: selection)
        let model = AnimalTimelineContainerViewModel()
        selection.select(nil)

        model.load(
            animalID: UUID(),
            using: reader,
            selection: selection,
            originatingHerdID: herdID,
            originatingSelectionRevision: 0
        )

        XCTAssertFalse(model.hasLoaded)
        XCTAssertEqual(reader.fetchCount, 0)
    }

    func testCurrentSelectionReportsReadErrorsWithoutLeakingAfterSwitch() {
        let herdID = UUID()
        let selection = AppCurrentHerdSelection(currentHerdID: herdID)
        let reader = TimelineHerdProbe(selection: selection)
        reader.shouldFail = true
        let model = AnimalTimelineContainerViewModel()
        let revision = selection.selectionRevision

        model.load(
            animalID: UUID(),
            using: reader,
            selection: selection,
            originatingHerdID: herdID,
            originatingSelectionRevision: revision
        )
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.hasCurrentEvents(
            for: selection,
            originatingHerdID: herdID,
            originatingSelectionRevision: revision
        ))

        selection.select(UUID())
        XCTAssertFalse(model.hasCurrentEvents(
            for: selection,
            originatingHerdID: herdID,
            originatingSelectionRevision: revision
        ))
    }

    private func makeEvent(_ title: String) -> AnimalTimelineEvent {
        AnimalTimelineEvent(
            id: UUID().uuidString,
            date: .now,
            type: .health,
            title: title,
            details: nil
        )
    }
}

@MainActor
private final class TimelineHerdProbe: AnimalTimelineReading {
    let selection: AppCurrentHerdSelection
    let eventsByHerd: [UUID: [AnimalTimelineEvent]]
    var shouldFail = false
    private(set) var fetchCount = 0

    init(
        selection: AppCurrentHerdSelection,
        eventsByHerd: [UUID: [AnimalTimelineEvent]] = [:]
    ) {
        self.selection = selection
        self.eventsByHerd = eventsByHerd
    }

    func fetchTimeline(id: UUID) throws -> [AnimalTimelineEvent] {
        fetchCount += 1
        if shouldFail { throw ProbeError.failed }
        return selection.currentHerdID.flatMap { eventsByHerd[$0] } ?? []
    }

    private enum ProbeError: Error {
        case failed
    }
}
