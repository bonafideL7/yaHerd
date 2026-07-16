import Foundation
import Observation

enum ApplicationFeatureArea: String, CaseIterable, Hashable, Sendable {
    case home
    case dashboard
    case animals
    case pastures
    case fieldChecks
    case workingSessions
    case collaboration
}

enum ApplicationMutationSource: Equatable, Sendable {
    case local(SharedDataMutationReason)
    case sharedStoreImport
}

struct ApplicationMutationEvent: Equatable, Sendable {
    let sequence: UInt64
    let source: ApplicationMutationSource
    let affectedAreas: Set<ApplicationFeatureArea>
}

@MainActor
protocol ApplicationMutationStreaming {
    var currentSequence: UInt64 { get }
    func events(after sequence: UInt64) -> AsyncStream<ApplicationMutationEvent>
}

@MainActor
protocol SuccessfulMutationRecording {
    func recordSuccessfulMutation(reason: SharedDataMutationReason)
}

/// Central application change stream. Repository decorators publish only after a command succeeds.
/// Feature models subscribe by affected area instead of relying on view-owned refresh tokens.
@MainActor
@Observable
final class ApplicationMutationCenter: ApplicationMutationStreaming {
    private static let retainedEventLimit = 64

    private(set) var latestEvent: ApplicationMutationEvent?
    private var nextSequence: UInt64 = 0
    private var retainedEvents: [ApplicationMutationEvent] = []
    private var continuations: [UUID: AsyncStream<ApplicationMutationEvent>.Continuation] = [:]

    var currentSequence: UInt64 {
        nextSequence
    }

    func recordSuccessfulMutation(reason: SharedDataMutationReason) {
        publish(source: .local(reason))
    }

    func recordSharedStoreImport() {
        publish(source: .sharedStoreImport)
    }

    func events(after sequence: UInt64) -> AsyncStream<ApplicationMutationEvent> {
        let subscriberID = UUID()
        let pendingEvents = retainedEvents.filter { $0.sequence > sequence }
        let (stream, continuation) = AsyncStream<ApplicationMutationEvent>.makeStream()

        continuations[subscriberID] = continuation
        pendingEvents.forEach { continuation.yield($0) }
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.continuations.removeValue(forKey: subscriberID)
            }
        }
        return stream
    }

    private func publish(source: ApplicationMutationSource) {
        nextSequence &+= 1
        let event = ApplicationMutationEvent(
            sequence: nextSequence,
            source: source,
            affectedAreas: affectedAreas(for: source)
        )
        latestEvent = event
        retainedEvents.append(event)
        if retainedEvents.count > Self.retainedEventLimit {
            retainedEvents.removeFirst(retainedEvents.count - Self.retainedEventLimit)
        }
        continuations.values.forEach { $0.yield(event) }
    }

    private func affectedAreas(for source: ApplicationMutationSource) -> Set<ApplicationFeatureArea> {
        switch source {
        case .sharedStoreImport:
            return Set(ApplicationFeatureArea.allCases)
        case .local(let reason):
            switch reason {
            case .herd:
                return [.home, .collaboration]
            case .animal:
                return [.home, .dashboard, .animals, .pastures]
            case .pasture:
                return [.home, .dashboard, .animals, .pastures, .fieldChecks, .workingSessions]
            case .dashboard:
                return [.home, .dashboard, .pastures]
            case .fieldCheck:
                return [.home, .dashboard, .fieldChecks]
            case .working:
                return [.home, .dashboard, .animals, .pastures, .workingSessions]
            case .tagColor:
                return [.home, .dashboard, .animals]
            case .sampleData:
                return Set(ApplicationFeatureArea.allCases)
            }
        }
    }
}

/// Records one successful local command and fans it out to UI invalidation and collaboration sync.
@MainActor
final class ApplicationMutationPipeline: SuccessfulMutationRecording {
    private let center: ApplicationMutationCenter
    private let sharingScheduler: HerdSharingMutationSyncScheduler

    init(
        center: ApplicationMutationCenter,
        sharingScheduler: HerdSharingMutationSyncScheduler
    ) {
        self.center = center
        self.sharingScheduler = sharingScheduler
    }

    func recordSuccessfulMutation(reason: SharedDataMutationReason) {
        center.recordSuccessfulMutation(reason: reason)
        sharingScheduler.requestSharedDataSyncAfterMutation(reason: reason)
    }
}
