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
  }

  private let userDefaults: UserDefaults
  private let storageKey: String
  private let maxStoredReviews: Int

  private(set) var latestReview: HerdSharingConflictReview?
  private(set) var reviewHistory: [HerdSharingConflictReview] = []

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

  func clearLatestReview() {
    guard !reviewHistory.isEmpty else {
      latestReview = nil
      userDefaults.removeObject(forKey: storageKey)
      return
    }

    reviewHistory.removeFirst()
    latestReview = reviewHistory.first
    persistOrRemoveIfEmpty()
  }

  func clearAllReviews() {
    latestReview = nil
    reviewHistory = []
    userDefaults.removeObject(forKey: storageKey)
  }

  private func load() {
    guard let data = userDefaults.data(forKey: storageKey) else {
      latestReview = nil
      reviewHistory = []
      return
    }

    do {
      let storedReviews = try JSONDecoder().decode(StoredConflictReviews.self, from: data)
      reviewHistory = Array(storedReviews.reviews.prefix(maxStoredReviews))
      latestReview = reviewHistory.first
    } catch {
      latestReview = nil
      reviewHistory = []
      userDefaults.removeObject(forKey: storageKey)
    }
  }

  private func persistOrRemoveIfEmpty() {
    guard !reviewHistory.isEmpty else {
      userDefaults.removeObject(forKey: storageKey)
      return
    }

    persist()
  }

  private func persist() {
    let storedReviews = StoredConflictReviews(reviews: reviewHistory)
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
