@MainActor
protocol PersistenceAssembly {
    func makeDependencies(
        dataAccessMode: AppDataAccessMode
    ) -> AppDependencies
}
