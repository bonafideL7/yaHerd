//
//  HerdCollaborationViewModel.swift
//  yaHerd
//

import Foundation
import Observation

@MainActor
@Observable
final class HerdCollaborationViewModel {
    private(set) var herd: HerdSummary?
    private(set) var readiness: HerdSharingReadiness?
    var draftName = ""
    var errorMessage: String?
    var successMessage: String?

    func load(
        herdRepository: any HerdRepository,
        sharingRepository: any HerdSharingRepository,
        storageMode: HerdStorageMode
    ) {
        do {
            let loadedHerd = try LoadCurrentHerdUseCase(repository: herdRepository).execute()
            herd = loadedHerd
            draftName = loadedHerd.name
            readiness = LoadHerdSharingReadinessUseCase(repository: sharingRepository).execute(
                herd: loadedHerd,
                storageMode: storageMode
            )
            errorMessage = nil
        } catch {
            herd = nil
            readiness = LoadHerdSharingReadinessUseCase(repository: sharingRepository).execute(
                herd: nil,
                storageMode: storageMode
            )
            errorMessage = error.localizedDescription
        }
    }

    func saveName(
        using repository: any HerdRepository,
        sharingRepository: any HerdSharingRepository,
        storageMode: HerdStorageMode
    ) {
        do {
            let renamedHerd = try RenameCurrentHerdUseCase(repository: repository).execute(name: draftName)
            herd = renamedHerd
            draftName = renamedHerd.name
            readiness = LoadHerdSharingReadinessUseCase(repository: sharingRepository).execute(
                herd: renamedHerd,
                storageMode: storageMode
            )
            successMessage = "Herd name saved."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    func resetDraftName() {
        draftName = herd?.name ?? ""
        errorMessage = nil
        successMessage = nil
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}
