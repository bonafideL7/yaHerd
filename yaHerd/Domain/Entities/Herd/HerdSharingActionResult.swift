//
//  HerdSharingActionResult.swift
//  yaHerd
//

struct HerdSharingActionResult: Equatable {
  let title: String
  let message: String
  let systemShare: HerdSystemShare?
  let conflictReview: HerdSharingConflictReview?

  init(
    title: String,
    message: String,
    systemShare: HerdSystemShare? = nil,
    conflictReview: HerdSharingConflictReview? = nil
  ) {
    self.title = title
    self.message = message
    self.systemShare = systemShare
    self.conflictReview = conflictReview
  }

  static func == (lhs: HerdSharingActionResult, rhs: HerdSharingActionResult) -> Bool {
    lhs.title == rhs.title
      && lhs.message == rhs.message
      && (lhs.systemShare == nil) == (rhs.systemShare == nil)
      && lhs.conflictReview == rhs.conflictReview
  }
}
