import Observation

@MainActor
protocol PersistenceAssembly {
    var storageActivity: StorageActivitySnapshot { get }

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
