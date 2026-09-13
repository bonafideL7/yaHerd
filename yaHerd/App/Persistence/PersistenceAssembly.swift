@MainActor
protocol PersistenceAssembly {
    func makeDependencies(
        tagColorDuplicateResolutionPolicy: TagColorDuplicateResolutionPolicy,
        dataAccessMode: AppDataAccessMode,
        storageMode: HerdStorageMode
    ) -> AppDependencies
}
