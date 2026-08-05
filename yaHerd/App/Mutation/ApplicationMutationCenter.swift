import Foundation
import Observation

enum ApplicationFeatureArea: String, CaseIterable, Hashable, Sendable {
    case home
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
    var homeRevision: UInt64 { get }
    var animalRevision: UInt64 { get }
    var pastureRevision: UInt64 { get }
    var fieldCheckRevision: UInt64 { get }
    var workingSessionRevision: UInt64 { get }
    var collaborationRevision: UInt64 { get }

    func revision(for area: ApplicationFeatureArea) -> UInt64
    func revisions(
        for area: ApplicationFeatureArea,
        after revision: UInt64
    ) -> AsyncStream<UInt64>
    func events() -> AsyncStream<ApplicationMutationEvent>
}

@MainActor
protocol ApplicationMutationStreamProviding {
    var applicationMutationStream: any ApplicationMutationStreaming { get }
}

@MainActor
protocol SuccessfulMutationRecording {
    func recordSuccessfulMutation(reason: SharedDataMutationReason)
}

/// Central application invalidation service. Repository decorators publish only after a command succeeds.
/// Per-feature revisions make invalidation durable for screens that begin listening after a mutation.
@MainActor
@Observable
final class ApplicationMutationCenter: ApplicationMutationStreaming {
    private(set) var latestEvent: ApplicationMutationEvent?
    private(set) var homeRevision: UInt64 = 0
    private(set) var animalRevision: UInt64 = 0
    private(set) var pastureRevision: UInt64 = 0
    private(set) var fieldCheckRevision: UInt64 = 0
    private(set) var workingSessionRevision: UInt64 = 0
    private(set) var collaborationRevision: UInt64 = 0

    private var nextSequence: UInt64 = 0
    private var eventContinuations: [
        UUID: AsyncStream<ApplicationMutationEvent>.Continuation
    ] = [:]
    private var revisionContinuations: [
        ApplicationFeatureArea: [UUID: AsyncStream<UInt64>.Continuation]
    ] = [:]

    var currentSequence: UInt64 {
        nextSequence
    }

    func recordSuccessfulMutation(reason: SharedDataMutationReason) {
        publish(source: .local(reason))
    }

    func recordSharedStoreImport() {
        publish(source: .sharedStoreImport)
    }

    func revision(for area: ApplicationFeatureArea) -> UInt64 {
        switch area {
        case .home:
            return homeRevision
        case .animals:
            return animalRevision
        case .pastures:
            return pastureRevision
        case .fieldChecks:
            return fieldCheckRevision
        case .workingSessions:
            return workingSessionRevision
        case .collaboration:
            return collaborationRevision
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

    func events() -> AsyncStream<ApplicationMutationEvent> {
        let subscriberID = UUID()
        let (stream, continuation) = AsyncStream<ApplicationMutationEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )

        eventContinuations[subscriberID] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.eventContinuations.removeValue(forKey: subscriberID)
            }
        }
        return stream
    }

    private func publish(source: ApplicationMutationSource) {
        let affectedAreas = affectedAreas(for: source)
        for area in affectedAreas {
            incrementRevision(for: area)
        }

        nextSequence &+= 1
        let event = ApplicationMutationEvent(
            sequence: nextSequence,
            source: source,
            affectedAreas: affectedAreas
        )
        latestEvent = event

        eventContinuations.values.forEach { $0.yield(event) }
        for area in affectedAreas {
            let currentRevision = revision(for: area)
            revisionContinuations[area]?.values.forEach { $0.yield(currentRevision) }
        }
    }

    private func incrementRevision(for area: ApplicationFeatureArea) {
        switch area {
        case .home:
            homeRevision &+= 1
        case .animals:
            animalRevision &+= 1
        case .pastures:
            pastureRevision &+= 1
        case .fieldChecks:
            fieldCheckRevision &+= 1
        case .workingSessions:
            workingSessionRevision &+= 1
        case .collaboration:
            collaborationRevision &+= 1
        }
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
                return [.home, .animals, .pastures, .fieldChecks, .workingSessions]
            case .pasture:
                return [.home, .animals, .pastures, .fieldChecks, .workingSessions]
            case .dashboard:
                return [.home, .pastures]
            case .fieldCheck:
                return [.home, .pastures, .fieldChecks]
            case .working:
                return [.home, .animals, .pastures, .fieldChecks, .workingSessions]
            case .tagColor:
                return [.home, .animals, .pastures, .fieldChecks, .workingSessions]
            case .sampleData:
                return Set(ApplicationFeatureArea.allCases)
            }
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
    var collaborationRevision: UInt64 { 0 }

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

    func events() -> AsyncStream<ApplicationMutationEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

/// Records one successful local command and fans it out to UI invalidation and collaboration sync.
@MainActor
final class ApplicationMutationPipeline:
    SuccessfulMutationRecording,
    ApplicationMutationStreamProviding
{
    private let center: ApplicationMutationCenter
    private let sharingScheduler: HerdSharingMutationSyncScheduler

    init(
        center: ApplicationMutationCenter,
        sharingScheduler: HerdSharingMutationSyncScheduler
    ) {
        self.center = center
        self.sharingScheduler = sharingScheduler
    }

    var applicationMutationStream: any ApplicationMutationStreaming {
        center
    }

    func recordSuccessfulMutation(reason: SharedDataMutationReason) {
        center.recordSuccessfulMutation(reason: reason)
        sharingScheduler.requestSharedDataSyncAfterMutation(reason: reason)
    }
}
