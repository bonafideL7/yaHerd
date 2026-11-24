@MainActor
protocol PersistenceAssembly {
    var storageActivity: StorageActivitySnapshot { get }

    func makeDependencies(
        dataAccessMode: AppDataAccessMode
    ) -> AppDependencies
}
