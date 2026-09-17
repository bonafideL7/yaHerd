@MainActor
final class AppDependencies {
    let animalFeatureDependencies: AnimalFeatureDependencies
    let pastureFeatureDependencies: PastureFeatureDependencies
    let fieldCheckFeatureDependencies: FieldCheckFeatureDependencies
    let workingSessionFeatureDependencies: WorkingSessionFeatureDependencies
    let homeFeatureDependencies: HomeFeatureDependencies

    let tagColorRepository: any TagColorRepository
    let herdRepository: any HerdRepository
    let applicationMutationCenter: ApplicationMutationCenter

    init(
        animalFeatureDependencies: AnimalFeatureDependencies,
        pastureFeatureDependencies: PastureFeatureDependencies,
        fieldCheckFeatureDependencies: FieldCheckFeatureDependencies,
        workingSessionFeatureDependencies: WorkingSessionFeatureDependencies,
        homeFeatureDependencies: HomeFeatureDependencies,
        tagColorRepository: any TagColorRepository,
        herdRepository: any HerdRepository,
        applicationMutationCenter: ApplicationMutationCenter
    ) {
        self.animalFeatureDependencies = animalFeatureDependencies
        self.pastureFeatureDependencies = pastureFeatureDependencies
        self.fieldCheckFeatureDependencies = fieldCheckFeatureDependencies
        self.workingSessionFeatureDependencies = workingSessionFeatureDependencies
        self.homeFeatureDependencies = homeFeatureDependencies
        self.tagColorRepository = tagColorRepository
        self.herdRepository = herdRepository
        self.applicationMutationCenter = applicationMutationCenter
    }
}
