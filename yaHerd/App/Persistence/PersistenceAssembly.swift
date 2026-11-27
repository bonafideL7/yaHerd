import Observation
import SwiftUI
import UIKit

@MainActor
protocol PersistenceAssembly {
    var storageActivity: StorageActivitySnapshot { get }

    func prepareSharingInterface(
        onChange: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor () -> Void
    ) async throws -> UIViewController

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
        let id = UUID()
        let controller: UIViewController
    }

    private(set) var isPreparing = false
    var presentation: Presentation?
    var errorMessage: String?
    @ObservationIgnored private let assembly: any PersistenceAssembly

    init(assembly: any PersistenceAssembly) {
        self.assembly = assembly
    }

    func open(onChange: @escaping @MainActor () -> Void) async {
        guard !isPreparing, presentation == nil else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            let controller = try await assembly.prepareSharingInterface(
                onChange: onChange,
                onFailure: { [weak self] in
                    self?.errorMessage = "Sharing changes could not be saved. Check iCloud activity and try again."
                    self?.presentation = nil
                    onChange()
                }
            )
            try Task.checkCancellation()
            presentation = Presentation(controller: controller)
            onChange()
        } catch is CancellationError {
            onChange()
        } catch {
            errorMessage = error.localizedDescription
            onChange()
        }
    }
}
