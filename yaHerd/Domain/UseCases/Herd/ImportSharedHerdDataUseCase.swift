//
//  ImportSharedHerdDataUseCase.swift
//  yaHerd
//

@MainActor
struct ImportSharedHerdDataUseCase {
  private let repository: any HerdSharingRepository

  init(repository: any HerdSharingRepository) {
    self.repository = repository
  }

  func execute(
    herd: HerdSummary?,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    try await repository.importSharedBridgeData(
      herd: herd,
      storageMode: storageMode
    )
  }
}
