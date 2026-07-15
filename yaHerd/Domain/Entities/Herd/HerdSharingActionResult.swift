//
//  HerdSharingActionResult.swift
//  yaHerd
//

struct HerdSharingActionResult: Equatable {
  let title: String
  let message: String
  let sharePresentation: HerdSharePresentationRequest?
  let conflictReview: HerdSharingConflictReview?
  let reconciliationReview: HerdSharingReconciliationReview?

  init(
    title: String,
    message: String,
    sharePresentation: HerdSharePresentationRequest? = nil,
    conflictReview: HerdSharingConflictReview? = nil,
    reconciliationReview: HerdSharingReconciliationReview? = nil
  ) {
    self.title = title
    self.message = message
    self.sharePresentation = sharePresentation
    self.conflictReview = conflictReview
    self.reconciliationReview = reconciliationReview
  }

  static func == (lhs: HerdSharingActionResult, rhs: HerdSharingActionResult) -> Bool {
    lhs.title == rhs.title
      && lhs.message == rhs.message
      && lhs.sharePresentation == rhs.sharePresentation
      && lhs.conflictReview == rhs.conflictReview
      && lhs.reconciliationReview == rhs.reconciliationReview
  }
}
