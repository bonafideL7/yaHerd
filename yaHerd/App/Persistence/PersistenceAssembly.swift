import Observation
import SwiftUI
import UIKit

@MainActor
protocol PersistenceAssembly {
    var storageActivity: StorageActivitySnapshot { get }

    func prepareSharingInterface(
        onChange: @escaping @MainActor @Sendable () -> Void,
        onFailure: @escaping @MainActor @Sendable () -> Void
    ) async throws -> UIViewController

    func stopSelectedHerdSharing(expectedRoot: URL) async throws
    func leaveSelectedHerd() async throws

    func makeDependencies(
        dataAccessMode: AppDataAccessMode
    ) -> AppDependencies
}

/// One observable application service supplies storage status to Settings and
/// the Herd chooser. Its snapshot contains no repository or transport objects.
@MainActor
@Observable
final class StorageActivityController {
    private(set) var snapshot: StorageActivitySnapshot

    @ObservationIgnored private let assembly: any PersistenceAssembly

    init(assembly: any PersistenceAssembly) {
        self.assembly = assembly
        snapshot = assembly.storageActivity
    }

    func refresh() {
        let latest = assembly.storageActivity
        if latest != snapshot {
            snapshot = latest
        }
    }
}

/// One presentation session per scene; native objects are hidden behind a
/// generic UIKit controller. Selection changes invalidate a pending request.
@MainActor
@Observable
final class HerdSharingController {
    struct Presentation: Identifiable {
        let id: UUID
        let controller: UIViewController
    }

    private(set) var isStopping = false
    private(set) var isLeaving = false
    private(set) var isPreparing = false
    var presentation: Presentation?
    var errorMessage: String?
    @ObservationIgnored private let assembly: any PersistenceAssembly

    init(assembly: any PersistenceAssembly) {
        self.assembly = assembly
    }

    func stop(expectedRoot: URL, onChange: @escaping @MainActor () -> Void) async {
        guard !isStopping, !isLeaving, !isPreparing, presentation == nil else { return }
        isStopping = true
        defer { isStopping = false }
        do {
            try await assembly.stopSelectedHerdSharing(expectedRoot: expectedRoot)
        } catch {
            errorMessage = "Could not remove all participant access. Refresh sharing information before retrying. \(error.localizedDescription)"
        }
        onChange()
    }

    func leave(onChange: @escaping @MainActor () -> Void) async {
        guard !isLeaving, !isPreparing else { return }
        isLeaving = true
        defer { isLeaving = false }
        do {
            try await assembly.leaveSelectedHerd()
        } catch {
            errorMessage = error.localizedDescription
        }
        onChange()
    }

    func open(onChange: @escaping @MainActor @Sendable () -> Void) async {
        guard !isPreparing, !isStopping, !isLeaving, presentation == nil else { return }
        isPreparing = true
        let sessionID = UUID()
        defer { isPreparing = false }
        do {
            let controller = try await assembly.prepareSharingInterface(
                onChange: onChange,
                onFailure: { [weak self] in
                    self?.errorMessage = "Sharing changes could not be saved. Check iCloud activity and try again."
                    if self?.presentation?.id == sessionID {
                        self?.presentation = nil
                    }
                    onChange()
                }
            )
            try Task.checkCancellation()
            presentation = Presentation(id: sessionID, controller: controller)
            onChange()
        } catch is CancellationError {
            onChange()
        } catch {
            errorMessage = error.localizedDescription
            onChange()
        }
    }
}
