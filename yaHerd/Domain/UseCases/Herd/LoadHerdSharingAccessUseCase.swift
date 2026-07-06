//
//  LoadHerdSharingAccessUseCase.swift
//  yaHerd
//

@MainActor
struct LoadHerdSharingAccessUseCase {
  private let repository: any HerdSharingRepository

  init(repository: any HerdSharingRepository) {
    self.repository = repository
  }

  func execute(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingAccess {
    try await repository.fetchSharingAccess(
      for: herd,
      storageMode: storageMode
    )
  }
}
