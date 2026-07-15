//
//  HerdSharingActionResult.swift
//  yaHerd
//

struct HerdSharingActionResult: Equatable {
  let title: String
  let message: String
  let systemShare: HerdSystemShare?
  let conflictReview: HerdSharingConflictReview?
  let reconciliationReview: HerdSharingReconciliationReview?

  init(
    title: String,
    message: String,
    systemShare: HerdSystemShare? = nil,
    conflictReview: HerdSharingConflictReview? = nil,
    reconciliationReview: HerdSharingReconciliationReview? = nil
  ) {
    self.title = title
    self.message = message
    self.systemShare = systemShare
    self.conflictReview = conflictReview
    self.reconciliationReview = reconciliationReview
  }

  static func == (lhs: HerdSharingActionResult, rhs: HerdSharingActionResult) -> Bool {
    lhs.title == rhs.title
      && lhs.message == rhs.message
      && (lhs.systemShare == nil) == (rhs.systemShare == nil)
      && lhs.conflictReview == rhs.conflictReview
      && lhs.reconciliationReview == rhs.reconciliationReview
  }
}
