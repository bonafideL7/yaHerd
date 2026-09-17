import Foundation
import Observation

enum ApplicationFeatureArea: String, CaseIterable, Hashable, Sendable {
    case home
    case dashboard
    case animals
    case pastures
    case fieldChecks
    case workingSessions
}

enum ApplicationMutationSource: Equatable, Sendable {
    case local(DataMutationReason)
}

struct ApplicationMutationEvent: Equatable, Sendable {
    let sequence: UInt64
    let source: ApplicationMutationSource
    let affectedAreas: Set<ApplicationFeatureArea>
}

@MainActor
protocol ApplicationMutationStreaming {
    var currentSequence: UInt64 { get }
    var homeRevision: UInt64 { get }
    var animalRevision: UInt64 { get }
    var pastureRevision: UInt64 { get }
    var fieldCheckRevision: UInt64 { get }
    var workingSessionRevision: UInt64 { get }

    func revision(for area: ApplicationFeatureArea) -> UInt64
    func revisions(
        for area: ApplicationFeatureArea,
        after revision: UInt64
    ) -> AsyncStream<UInt64>
    func events(after sequence: UInt64) -> AsyncStream<ApplicationMutationEvent>
}

@MainActor
protocol ApplicationMutationStreamProviding {
    var applicationMutationStream: any ApplicationMutationStreaming { get }
}

@MainActor
protocol SuccessfulMutationRecording {
    func recordSuccessfulMutation(reason: DataMutationReason)
}

/// Central application change stream. Repository decorators publish only after a local command
/// succeeds so dependent screens can invalidate stale read models without persistence coupling.
@MainActor
@Observable
final class ApplicationMutationCenter: ApplicationMutationStreaming {
    private static let retainedEventLimit = 64

    private(set) var latestEvent: ApplicationMutationEvent?
    private(set) var homeRevision: UInt64 = 0
    private(set) var dashboardRevision: UInt64 = 0
    private(set) var animalRevision: UInt64 = 0
    private(set) var pastureRevision: UInt64 = 0
    private(set) var fieldCheckRevision: UInt64 = 0
    private(set) var workingSessionRevision: UInt64 = 0

    private var nextSequence: UInt64 = 0
    private var retainedEvents: [ApplicationMutationEvent] = []
    private var eventContinuations: [UUID: AsyncStream<ApplicationMutationEvent>.Continuation] = [:]
    private var revisionContinuations: [
        ApplicationFeatureArea: [UUID: AsyncStream<UInt64>.Continuation]
    ] = [:]

    var currentSequence: UInt64 {
        nextSequence
    }

    func recordSuccessfulMutation(reason: DataMutationReason) {
        publish(reason: reason)
    }

    func revision(for area: ApplicationFeatureArea) -> UInt64 {
        switch area {
        case .home:
            return homeRevision
        case .dashboard:
            return dashboardRevision
        case .animals:
            return animalRevision
        case .pastures:
            return pastureRevision
        case .fieldChecks:
            return fieldCheckRevision
        case .workingSessions:
            return workingSessionRevision
        }
    }

    func revisions(
        for area: ApplicationFeatureArea,
        after revision: UInt64
    ) -> AsyncStream<UInt64> {
        let subscriberID = UUID()
        let currentRevision = self.revision(for: area)
        let (stream, continuation) = AsyncStream<UInt64>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )

        revisionContinuations[area, default: [:]][subscriberID] = continuation
        if currentRevision > revision {
            continuation.yield(currentRevision)
        }
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.revisionContinuations[area]?.removeValue(forKey: subscriberID)
            }
        }
        return stream
    }

    func events(after sequence: UInt64) -> AsyncStream<ApplicationMutationEvent> {
        let subscriberID = UUID()
        let pendingEvents = retainedEvents.filter { $0.sequence > sequence }
        let (stream, continuation) = AsyncStream<ApplicationMutationEvent>.makeStream()

        eventContinuations[subscriberID] = continuation
        pendingEvents.forEach { continuation.yield($0) }
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.eventContinuations.removeValue(forKey: subscriberID)
            }
        }
        return stream
    }

    private func publish(reason: DataMutationReason) {
        let affectedAreas = affectedAreas(for: reason)
        incrementRevisions(for: affectedAreas)

        nextSequence &+= 1
        let event = ApplicationMutationEvent(
            sequence: nextSequence,
            source: .local(reason),
            affectedAreas: affectedAreas
        )
        latestEvent = event
        retainedEvents.append(event)
        if retainedEvents.count > Self.retainedEventLimit {
            retainedEvents.removeFirst(retainedEvents.count - Self.retainedEventLimit)
        }
        eventContinuations.values.forEach { $0.yield(event) }

        for area in affectedAreas {
            let currentRevision = revision(for: area)
            revisionContinuations[area]?.values.forEach { $0.yield(currentRevision) }
        }
    }

    private func incrementRevisions(for affectedAreas: Set<ApplicationFeatureArea>) {
        if affectedAreas.contains(.home) {
            homeRevision &+= 1
        }
        if affectedAreas.contains(.dashboard) {
            dashboardRevision &+= 1
        }
        if affectedAreas.contains(.animals) {
            animalRevision &+= 1
        }
        if affectedAreas.contains(.pastures) {
            pastureRevision &+= 1
        }
        if affectedAreas.contains(.fieldChecks) {
            fieldCheckRevision &+= 1
        }
        if affectedAreas.contains(.workingSessions) {
            workingSessionRevision &+= 1
        }
    }

    private func affectedAreas(for reason: DataMutationReason) -> Set<ApplicationFeatureArea> {
        switch reason {
        case .herd:
            return [.home]
        case .animal:
            return [.home, .dashboard, .animals, .pastures, .fieldChecks, .workingSessions]
        case .pasture:
            return [.home, .dashboard, .animals, .pastures, .fieldChecks, .workingSessions]
        case .dashboard:
            return [.home, .dashboard, .pastures]
        case .fieldCheck:
            return [.home, .dashboard, .pastures, .fieldChecks]
        case .working:
            return [.home, .dashboard, .animals, .pastures, .fieldChecks, .workingSessions]
        case .tagColor:
            return [.home, .dashboard, .animals, .pastures, .fieldChecks, .workingSessions]
        case .sampleData:
            return Set(ApplicationFeatureArea.allCases)
        }
    }
}

@MainActor
struct InactiveApplicationMutationStream: ApplicationMutationStreaming {
    nonisolated init() {}

    var currentSequence: UInt64 { 0 }
    var homeRevision: UInt64 { 0 }
    var animalRevision: UInt64 { 0 }
    var pastureRevision: UInt64 { 0 }
    var fieldCheckRevision: UInt64 { 0 }
    var workingSessionRevision: UInt64 { 0 }

    func revision(for area: ApplicationFeatureArea) -> UInt64 {
        0
    }

    func revisions(
        for area: ApplicationFeatureArea,
        after revision: UInt64
    ) -> AsyncStream<UInt64> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func events(after sequence: UInt64) -> AsyncStream<ApplicationMutationEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

@MainActor
final class ApplicationMutationPipeline:
    SuccessfulMutationRecording,
    ApplicationMutationStreamProviding
{
    private let center: ApplicationMutationCenter

    init(center: ApplicationMutationCenter) {
        self.center = center
    }

    var applicationMutationStream: any ApplicationMutationStreaming {
        center
    }

    func recordSuccessfulMutation(reason: DataMutationReason) {
        center.recordSuccessfulMutation(reason: reason)
    }
}
