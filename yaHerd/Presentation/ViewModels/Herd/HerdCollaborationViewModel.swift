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
  private(set) var sharingAccess: HerdSharingAccess?
  private(set) var sharingAccessMessage: String?
  private(set) var isSharingActionInProgress = false
  var draftName = ""
  var errorMessage: String?
  var successMessage: String?
  var systemShare: HerdSystemShare?

  var canStartSharing: Bool {
    readiness?.shareActionEnabled == true && herd != nil && !isSharingActionInProgress
  }

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
      sharingAccess = nil
      sharingAccessMessage = nil
      errorMessage = nil
    } catch {
      herd = nil
      sharingAccess = nil
      sharingAccessMessage = nil
      readiness = LoadHerdSharingReadinessUseCase(repository: sharingRepository).execute(
        herd: nil,
        storageMode: storageMode
      )
      errorMessage = error.localizedDescription
    }
  }

  func refreshSharingAccess(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) async {
    do {
      let access = try await LoadHerdSharingAccessUseCase(repository: sharingRepository).execute(
        herd: herd,
        storageMode: storageMode
      )
      sharingAccess = access
      sharingAccessMessage = nil
    } catch HerdSharingActionError.iCloudSyncRequired {
      sharingAccess = nil
      sharingAccessMessage = "Enable iCloud Sync to inspect CloudKit share permissions."
    } catch HerdSharingActionError.shareRootMissing {
      sharingAccess = nil
      sharingAccessMessage = "No Herd share root is available yet."
    } catch {
      sharingAccess = nil
      sharingAccessMessage = error.localizedDescription
    }
  }

  func saveName(
    using repository: any HerdRepository,
    sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) {
    do {
      let renamedHerd = try RenameCurrentHerdUseCase(repository: repository).execute(
        name: draftName)
      herd = renamedHerd
      draftName = renamedHerd.name
      readiness = LoadHerdSharingReadinessUseCase(repository: sharingRepository).execute(
        herd: renamedHerd,
        storageMode: storageMode
      )
      sharingAccess = nil
      sharingAccessMessage = nil
      successMessage = "Herd name saved."
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
      successMessage = nil
    }
  }

  func startSharing(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) async {
    isSharingActionInProgress = true
    defer { isSharingActionInProgress = false }

    do {
      let result = try await StartHerdSharingUseCase(repository: sharingRepository).execute(
        herd: herd,
        storageMode: storageMode
      )
      systemShare = result.systemShare
      successMessage = result.systemShare == nil ? "\(result.title): \(result.message)" : nil
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
      successMessage = nil
      systemShare = nil
    }
  }

  @discardableResult
  func acceptPendingInvitation(
    _ invitation: HerdShareInvitation?,
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) async -> Bool {
    isSharingActionInProgress = true
    defer { isSharingActionInProgress = false }

    do {
      let result = try await AcceptHerdShareInvitationUseCase(repository: sharingRepository)
        .execute(
          invitation: invitation,
          storageMode: storageMode
        )
      successMessage = "\(result.title): \(result.message)"
      errorMessage = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      successMessage = nil
      return false
    }
  }

  @discardableResult
  func importSharedBridgeData(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) async -> Bool {
    isSharingActionInProgress = true
    defer { isSharingActionInProgress = false }

    do {
      let result = try await ImportSharedHerdDataUseCase(repository: sharingRepository).execute(
        storageMode: storageMode
      )
      successMessage = "\(result.title): \(result.message)"
      errorMessage = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      successMessage = nil
      return false
    }
  }

  @discardableResult
  func syncSharedBridgeData(
    using sharingRepository: any HerdSharingRepository,
    storageMode: HerdStorageMode
  ) async -> Bool {
    isSharingActionInProgress = true
    defer { isSharingActionInProgress = false }

    do {
      let result = try await SyncSharedHerdDataUseCase(repository: sharingRepository).execute(
        herd: herd,
        storageMode: storageMode
      )
      successMessage = "\(result.title): \(result.message)"
      errorMessage = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      successMessage = nil
      return false
    }
  }

  func dismissSystemShare() {
    systemShare = nil
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
