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
    case collaborationStateChange
    case sharedStoreImport
    case publicIDRepair
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
    var identityRevision: UInt64 { get }

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
    func recordSuccessfulMutation(reason: SharedDataMutationReason)
}

/// Central application change stream. Repository decorators publish only after a command succeeds.
/// Existing event replay remains available while per-feature revisions make invalidation durable
/// for screens that begin listening after a mutation.
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
    private(set) var collaborationRevision: UInt64 = 0
    private(set) var identityRevision: UInt64 = 0

    private var nextSequence: UInt64 = 0
    private var retainedEvents: [ApplicationMutationEvent] = []
    private var eventContinuations: [UUID: AsyncStream<ApplicationMutationEvent>.Continuation] = [:]
    private var revisionContinuations: [
        ApplicationFeatureArea: [UUID: AsyncStream<UInt64>.Continuation]
    ] = [:]

    var currentSequence: UInt64 {
        nextSequence
    }

    func recordSuccessfulMutation(reason: SharedDataMutationReason) {
        publish(source: .local(reason))
    }

    func recordCollaborationStateChange() {
        publish(source: .collaborationStateChange)
    }

    func recordSharedStoreImport() {
        publish(source: .sharedStoreImport)
    }

    func recordPublicIDRepair() {
        publish(source: .publicIDRepair)
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

    private func publish(source: ApplicationMutationSource) {
        let affectedAreas = affectedAreas(for: source)
        incrementRevisions(for: affectedAreas)
        incrementIdentityRevisionIfNeeded(for: source)

        nextSequence &+= 1
        let event = ApplicationMutationEvent(
            sequence: nextSequence,
            source: source,
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
        if affectedAreas.contains(.collaboration) {
            collaborationRevision &+= 1
        }
    }

    private func incrementIdentityRevisionIfNeeded(for source: ApplicationMutationSource) {
        switch source {
        case .sharedStoreImport, .publicIDRepair:
            identityRevision &+= 1
        case .local, .collaborationStateChange:
            break
        }
    }

    private func affectedAreas(for source: ApplicationMutationSource) -> Set<ApplicationFeatureArea> {
        switch source {
        case .collaborationStateChange:
            return [.collaboration]
        case .sharedStoreImport, .publicIDRepair:
            return Set(ApplicationFeatureArea.allCases)
        case .local(let reason):
            switch reason {
            case .herd:
                return [.home, .collaboration]
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
    var identityRevision: UInt64 { 0 }

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

/// Publishes after each transactional SwiftData public-ID repair commit, including intermediate
/// recovery boundaries, before later verification or bridge convergence can fail.
actor MutationPublishingPublicIDRepairTransactionalService:
    PublicIDRepairTransactionalService,
    PublicIDRepairTransactionalRecovering
{
    private let base: any PublicIDRepairTransactionalService
    private let mutationCenter: ApplicationMutationCenter

    init(
        base: any PublicIDRepairTransactionalService,
        mutationCenter: ApplicationMutationCenter
    ) {
        self.base = base
        self.mutationCenter = mutationCenter
    }

    func scan() async throws -> PublicIDRepairAssessment {
        try await base.scan()
    }

    func repair(
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit
    ) async throws -> PublicIDRepairReport {
        let report = try await base.repair(
            resolutions: resolutions,
            willCommit: willCommit
        )
        await mutationCenter.recordPublicIDRepair()
        return report
    }

    func commitState(for report: PublicIDRepairReport) async throws -> PublicIDRepairCommitState {
        try await base.commitState(for: report)
    }

    func assessIndeterminateRecovery(
        for report: PublicIDRepairReport
    ) async throws -> PublicIDRepairIndeterminateRecoveryAssessment {
        try await base.assessIndeterminateRecovery(for: report)
    }

    func recoverIndeterminateRepair(
        report: PublicIDRepairReport,
        action: PublicIDRepairRecoveryChoice,
        willCommit: PublicIDRepairWillCommit,
        didCommit: PublicIDRepairDidCommit
    ) async throws -> PublicIDRepairReport {
        try await base.recoverIndeterminateRepair(
            report: report,
            action: action,
            willCommit: willCommit,
            didCommit: { [mutationCenter] in
                mutationCenter.recordPublicIDRepair()
                await didCommit()
            }
        )
    }

    func resolveIndeterminateRecovery(
        report: PublicIDRepairReport,
        resolutions: [PublicIDRepairReferenceResolution],
        willCommit: PublicIDRepairWillCommit,
        didCommit: PublicIDRepairDidCommit
    ) async throws -> PublicIDRepairReport {
        try await base.resolveIndeterminateRecovery(
            report: report,
            resolutions: resolutions,
            willCommit: willCommit,
            didCommit: { [mutationCenter] in
                mutationCenter.recordPublicIDRepair()
                await didCommit()
            }
        )
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
