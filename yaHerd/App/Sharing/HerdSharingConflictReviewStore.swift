//
//  HerdSharingConflictReviewStore.swift
//  yaHerd
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class HerdSharingConflictReviewStore {
  private struct StoredConflictReviews: Codable, Equatable {
    var reviews: [HerdSharingConflictReview]
    var resolutions: [HerdSharingConflictResolution]?
  }

  private let userDefaults: UserDefaults
  private let storageKey: String
  private let maxStoredReviews: Int

  private(set) var latestReview: HerdSharingConflictReview?
  private(set) var reviewHistory: [HerdSharingConflictReview] = []
  private(set) var resolutionHistory: [HerdSharingConflictResolution] = []

  init(
    userDefaults: UserDefaults = .standard,
    storageKey: String = "ltd.yaherd.herdSharingConflictReviews",
    maxStoredReviews: Int = 20
  ) {
    self.userDefaults = userDefaults
    self.storageKey = storageKey
    self.maxStoredReviews = max(1, maxStoredReviews)
    load()
  }

  func record(_ review: HerdSharingConflictReview?) {
    guard let review, review.hasConflicts else { return }

    reviewHistory.removeAll { storedReview in
      storedReview.id == review.id
    }
    reviewHistory.insert(review, at: 0)
    if reviewHistory.count > maxStoredReviews {
      reviewHistory = Array(reviewHistory.prefix(maxStoredReviews))
    }
    latestReview = reviewHistory.first
    persist()
  }

  @discardableResult
  func resolve(
    _ review: HerdSharingConflictReview,
    choice: HerdSharingConflictResolutionChoice,
    resolvedAt: Date = .now,
    restoredLocalFieldSelections: [HerdSharingLocalFieldRestoreSelection] = []
  ) -> HerdSharingConflictResolution? {
    guard review.hasConflicts else { return nil }

    let resolution = HerdSharingConflictResolution(
      review: review,
      resolvedAt: resolvedAt,
      choice: choice,
      restoredLocalFieldSelections: restoredLocalFieldSelections
    )
    resolutionHistory.removeAll { $0.reviewID == resolution.reviewID }
    resolutionHistory.insert(resolution, at: 0)
    if resolutionHistory.count > maxStoredReviews {
      resolutionHistory = Array(resolutionHistory.prefix(maxStoredReviews))
    }

    reviewHistory.removeAll { $0.id == review.id }
    latestReview = reviewHistory.first
    persistOrRemoveIfEmpty()
    return resolution
  }

  func clearLatestReview() {
    guard !reviewHistory.isEmpty else {
      latestReview = nil
      persistOrRemoveIfEmpty()
      return
    }

    reviewHistory.removeFirst()
    latestReview = reviewHistory.first
    persistOrRemoveIfEmpty()
  }

  func clearAllReviews() {
    latestReview = nil
    reviewHistory = []
    persistOrRemoveIfEmpty()
  }

  func clearResolutionHistory() {
    resolutionHistory = []
    persistOrRemoveIfEmpty()
  }

  private func load() {
    guard let data = userDefaults.data(forKey: storageKey) else {
      latestReview = nil
      reviewHistory = []
      resolutionHistory = []
      return
    }

    do {
      let storedReviews = try JSONDecoder().decode(StoredConflictReviews.self, from: data)
      reviewHistory = Array(storedReviews.reviews.prefix(maxStoredReviews))
      resolutionHistory = Array((storedReviews.resolutions ?? []).prefix(maxStoredReviews))
      latestReview = reviewHistory.first
    } catch {
      latestReview = nil
      reviewHistory = []
      resolutionHistory = []
      userDefaults.removeObject(forKey: storageKey)
    }
  }

  private func persistOrRemoveIfEmpty() {
    guard !reviewHistory.isEmpty || !resolutionHistory.isEmpty else {
      userDefaults.removeObject(forKey: storageKey)
      return
    }

    persist()
  }

  private func persist() {
    let storedReviews = StoredConflictReviews(
      reviews: reviewHistory,
      resolutions: resolutionHistory
    )
    do {
      let data = try JSONEncoder().encode(storedReviews)
      userDefaults.set(data, forKey: storageKey)
    } catch {
      assertionFailure(
        "Failed to persist herd sharing conflict reviews: \(error.localizedDescription)")
    }
  }
}

private struct HerdSharingConflictReviewStoreKey: EnvironmentKey {
  static let defaultValue: HerdSharingConflictReviewStore? = nil
}

extension EnvironmentValues {
  var herdSharingConflictReviewStore: HerdSharingConflictReviewStore? {
    get { self[HerdSharingConflictReviewStoreKey.self] }
    set { self[HerdSharingConflictReviewStoreKey.self] = newValue }
  }
}
