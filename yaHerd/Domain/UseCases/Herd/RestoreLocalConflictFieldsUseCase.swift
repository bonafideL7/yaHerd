//
//  RestoreLocalConflictFieldsUseCase.swift
//  yaHerd
//

@MainActor
struct RestoreLocalConflictFieldsUseCase {
  private let repository: any HerdSharingRepository

  init(repository: any HerdSharingRepository) {
    self.repository = repository
  }

  func execute(
    selections: [HerdSharingLocalFieldRestoreSelection],
    review: HerdSharingConflictReview,
    storageMode: HerdStorageMode
  ) async throws -> HerdSharingActionResult {
    try await repository.restoreLocalFields(
      selections,
      in: review,
      storageMode: storageMode
    )
  }
}
