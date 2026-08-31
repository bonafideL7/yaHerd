import Foundation
import SwiftUI

nonisolated struct PastureFeatureDependencies {
    let listRepository: any PastureListRepository
    let createRepository: any PastureCreateRepository
    let detailRepository: any PastureDetailEditingRepository
    let groupListRepository: any PastureGroupListRepository
    let groupDetailRepository: any PastureGroupDetailRepository
    let groupEditorRepository: any PastureGroupEditorRepository
    let referenceReader: any PastureReferenceDataReader
    let animalMover: any AnimalPastureMoving
    let fieldCheckArchiveWriter: any FieldCheckPastureArchiveWriter
    let mutationStream: any ApplicationMutationStreaming

    nonisolated init(
        listRepository: any PastureListRepository,
        createRepository: any PastureCreateRepository,
        detailRepository: any PastureDetailEditingRepository,
        groupListRepository: any PastureGroupListRepository,
        groupDetailRepository: any PastureGroupDetailRepository,
        groupEditorRepository: any PastureGroupEditorRepository,
        referenceReader: any PastureReferenceDataReader,
        animalMover: any AnimalPastureMoving,
        fieldCheckArchiveWriter: any FieldCheckPastureArchiveWriter,
        mutationStream: any ApplicationMutationStreaming
    ) {
        self.listRepository = listRepository
        self.createRepository = createRepository
        self.detailRepository = detailRepository
        self.groupListRepository = groupListRepository
        self.groupDetailRepository = groupDetailRepository
        self.groupEditorRepository = groupEditorRepository
        self.referenceReader = referenceReader
        self.animalMover = animalMover
        self.fieldCheckArchiveWriter = fieldCheckArchiveWriter
        self.mutationStream = mutationStream
    }

    @MainActor
    init(
        pastureRepository: any PastureRepository,
        animalMover: any AnimalPastureMoving,
        fieldCheckArchiveWriter: any FieldCheckPastureArchiveWriter,
        mutationStream: any ApplicationMutationStreaming
    ) {
        self.init(
            listRepository: pastureRepository,
            createRepository: pastureRepository,
            detailRepository: pastureRepository,
            groupListRepository: pastureRepository,
            groupDetailRepository: pastureRepository,
            groupEditorRepository: pastureRepository,
            referenceReader: pastureRepository,
            animalMover: animalMover,
            fieldCheckArchiveWriter: fieldCheckArchiveWriter,
            mutationStream: mutationStream
        )
    }

    @MainActor
    static func preview(
        listRepository: (any PastureListRepository)? = nil,
        createRepository: (any PastureCreateRepository)? = nil,
        detailRepository: (any PastureDetailEditingRepository)? = nil,
        groupListRepository: (any PastureGroupListRepository)? = nil,
        groupDetailRepository: (any PastureGroupDetailRepository)? = nil,
        groupEditorRepository: (any PastureGroupEditorRepository)? = nil,
        referenceReader: (any PastureReferenceDataReader)? = nil,
        animalMover: (any AnimalPastureMoving)? = nil,
        fieldCheckArchiveWriter: (any FieldCheckPastureArchiveWriter)? = nil,
        mutationStream: (any ApplicationMutationStreaming)? = nil
    ) -> Self {
        let missingRepository = MissingPastureRepository()
        return Self(
            listRepository: listRepository ?? missingRepository,
            createRepository: createRepository ?? missingRepository,
            detailRepository: detailRepository ?? missingRepository,
            groupListRepository: groupListRepository ?? missingRepository,
            groupDetailRepository: groupDetailRepository ?? missingRepository,
            groupEditorRepository: groupEditorRepository ?? missingRepository,
            referenceReader: referenceReader ?? missingRepository,
            animalMover: animalMover ?? MissingPastureAnimalMover(),
            fieldCheckArchiveWriter: fieldCheckArchiveWriter ?? MissingPastureFieldCheckArchiveWriter(),
            mutationStream: mutationStream ?? InactiveApplicationMutationStream()
        )
    }
}

private enum MissingPastureFeatureDependencyError: LocalizedError {
    case dependency(String)

    var errorDescription: String? {
        switch self {
        case .dependency(let name):
            return "\(name) has not been configured."
        }
    }
}

private struct MissingPastureRepository: PastureRepository {
    nonisolated init(environmentFallback _: Void = ()) {}

    private func missing(_ name: String) -> MissingPastureFeatureDependencyError {
        .dependency(name)
    }

    func fetchPastures() throws -> [PastureSummary] { throw missing("Pasture list repository") }
    func fetchPastureDetail(id: UUID) throws -> PastureDetailSnapshot? { throw missing("Pasture detail repository") }
    func fetchResidentAnimals(pastureID: UUID) throws -> [AnimalSummary] { throw missing("Pasture resident animal reader") }
    func validatePastureIDsExist(_ ids: [UUID]) throws { throw missing("Pasture existence checker") }
    func fetchPastureOptions() throws -> [PastureOption] { throw missing("Pasture reference reader") }
    func nameExists(_ name: String, excluding id: UUID?) throws -> Bool { throw missing("Pasture name checker") }
    func create(input: PastureInput) throws -> PastureDetailSnapshot { throw missing("Pasture creator") }
    func update(id: UUID, input: PastureInput) throws -> PastureDetailSnapshot { throw missing("Pasture updater") }
    func reorder(ids: [UUID]) throws { throw missing("Pasture order writer") }
    func delete(ids: [UUID]) throws { throw missing("Pasture deleter") }
    func fetchPastureGroups() throws -> [PastureGroupSummary] { throw missing("Pasture group list repository") }
    func fetchPastureGroupDetail(id: UUID) throws -> PastureGroupDetailSnapshot? { throw missing("Pasture group detail repository") }
    func validatePastureGroupIDsExist(_ ids: [UUID]) throws { throw missing("Pasture group existence checker") }
    func groupNameExists(_ name: String, excluding id: UUID?) throws -> Bool { throw missing("Pasture group name checker") }
    func createGroup(input: PastureGroupInput) throws -> PastureGroupDetailSnapshot { throw missing("Pasture group creator") }
    func updateGroup(id: UUID, input: PastureGroupInput) throws -> PastureGroupDetailSnapshot { throw missing("Pasture group updater") }
    func deleteGroups(ids: [UUID]) throws { throw missing("Pasture group deleter") }
    func assignPasture(id pastureID: UUID, toGroupID groupID: UUID?) throws { throw missing("Pasture group assignment writer") }
}

private struct MissingPastureAnimalMover: AnimalPastureMoving {
    nonisolated init(environmentFallback _: Void = ()) {}

    func move(ids: [UUID], toPastureID: UUID?) throws {
        throw MissingPastureFeatureDependencyError.dependency("Animal pasture mover")
    }
}

private struct MissingPastureFieldCheckArchiveWriter: FieldCheckPastureArchiveWriter {
    nonisolated init(environmentFallback _: Void = ()) {}

    func archiveSessionsForDeletedPastures(_ ids: [UUID], archivedAt: Date) throws {
        throw MissingPastureFeatureDependencyError.dependency("Field-check pasture archive writer")
    }
}

private struct PastureFeatureDependenciesKey: EnvironmentKey {
    static var defaultValue: PastureFeatureDependencies {
        PastureFeatureDependencies(
            listRepository: MissingPastureRepository(),
            createRepository: MissingPastureRepository(),
            detailRepository: MissingPastureRepository(),
            groupListRepository: MissingPastureRepository(),
            groupDetailRepository: MissingPastureRepository(),
            groupEditorRepository: MissingPastureRepository(),
            referenceReader: MissingPastureRepository(),
            animalMover: MissingPastureAnimalMover(),
            fieldCheckArchiveWriter: MissingPastureFieldCheckArchiveWriter(),
            mutationStream: InactiveApplicationMutationStream()
        )
    }
}

extension EnvironmentValues {
    var pastureFeatureDependencies: PastureFeatureDependencies {
        get { self[PastureFeatureDependenciesKey.self] }
        set { self[PastureFeatureDependenciesKey.self] = newValue }
    }
}
