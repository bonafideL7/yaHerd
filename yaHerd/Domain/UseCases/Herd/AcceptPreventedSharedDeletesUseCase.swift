//
//  AcceptPreventedSharedDeletesUseCase.swift
//  yaHerd
//

@MainActor
struct AcceptPreventedSharedDeletesUseCase {
  private let repository: any HerdSharingRepository

  init(repository: any HerdSharingRepository) {
    self.repository = repository
  }

  func execute(
    review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    try await repository.acceptPreventedSharedDeletes(
      in: review,
      storageMode: storageMode
    )
  }
}
