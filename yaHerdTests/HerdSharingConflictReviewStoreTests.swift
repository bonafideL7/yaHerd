//
//  HerdSharingConflictReviewStoreTests.swift
//  yaHerdTests
//

import XCTest

@testable import yaHerd

@MainActor
final class HerdSharingConflictReviewStoreTests: XCTestCase {
  func testRecordPersistsLatestConflictReviewAcrossStoreInstances() {
    let suiteName = "HerdSharingConflictReviewStoreTests.record.\(UUID().uuidString)"
    let userDefaults = makeUserDefaults(suiteName: suiteName)
    let review = makeReview(sourceDescription: "Manual import", seconds: 10)

    let firstStore = HerdSharingConflictReviewStore(
      userDefaults: userDefaults,
      storageKey: "conflicts",
      maxStoredReviews: 5
    )
    firstStore.record(review)

    let secondStore = HerdSharingConflictReviewStore(
      userDefaults: userDefaults,
      storageKey: "conflicts",
      maxStoredReviews: 5
    )

    XCTAssertEqual(secondStore.latestReview, review)
    XCTAssertEqual(secondStore.reviewHistory, [review])
    userDefaults.removePersistentDomain(forName: suiteName)
  }

  func testRecordIgnoresNilAndNoConflictReviews() {
    let suiteName = "HerdSharingConflictReviewStoreTests.ignore.\(UUID().uuidString)"
    let userDefaults = makeUserDefaults(suiteName: suiteName)
    let store = HerdSharingConflictReviewStore(
      userDefaults: userDefaults,
      storageKey: "conflicts",
      maxStoredReviews: 5
    )

    let noConflictReview = HerdSharingConflictReview(
      title: "No conflicts",
      sourceDescription: "Manual import",
      detectedAt: Date(timeIntervalSince1970: 20),
      existingLocalRecordUpdateCount: 0,
      preventedDeleteConflicts: []
    )

    store.record(nil)
    store.record(noConflictReview)

    XCTAssertNil(store.latestReview)
    XCTAssertTrue(store.reviewHistory.isEmpty)
    userDefaults.removePersistentDomain(forName: suiteName)
  }

  func testKeepsMostRecentReviewsAndTrimsHistory() {
    let suiteName = "HerdSharingConflictReviewStoreTests.trim.\(UUID().uuidString)"
    let userDefaults = makeUserDefaults(suiteName: suiteName)
    let store = HerdSharingConflictReviewStore(
      userDefaults: userDefaults,
      storageKey: "conflicts",
      maxStoredReviews: 2
    )
    let oldest = makeReview(sourceDescription: "Oldest", seconds: 10)
    let middle = makeReview(sourceDescription: "Middle", seconds: 20)
    let newest = makeReview(sourceDescription: "Newest", seconds: 30)

    store.record(oldest)
    store.record(middle)
    store.record(newest)

    XCTAssertEqual(store.latestReview, newest)
    XCTAssertEqual(store.reviewHistory, [newest, middle])
    userDefaults.removePersistentDomain(forName: suiteName)
  }

  func testClearLatestPromotesPreviousReview() {
    let suiteName = "HerdSharingConflictReviewStoreTests.clearLatest.\(UUID().uuidString)"
    let userDefaults = makeUserDefaults(suiteName: suiteName)
    let store = HerdSharingConflictReviewStore(
      userDefaults: userDefaults,
      storageKey: "conflicts",
      maxStoredReviews: 5
    )
    let older = makeReview(sourceDescription: "Older", seconds: 10)
    let newer = makeReview(sourceDescription: "Newer", seconds: 20)

    store.record(older)
    store.record(newer)
    store.clearLatestReview()

    XCTAssertEqual(store.latestReview, older)
    XCTAssertEqual(store.reviewHistory, [older])
    userDefaults.removePersistentDomain(forName: suiteName)
  }

  private func makeUserDefaults(suiteName: String) -> UserDefaults {
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    return userDefaults
  }

  private func makeReview(sourceDescription: String, seconds: TimeInterval)
    -> HerdSharingConflictReview
  {
    HerdSharingConflictReview(
      title: "Shared-data conflicts detected",
      sourceDescription: sourceDescription,
      detectedAt: Date(timeIntervalSince1970: seconds),
      existingLocalRecordUpdateCount: 1,
      preventedDeleteConflicts: [
        HerdSharingPreventedDeleteConflict(
          sourceEntityName: "SharedAnimalRecord",
          publicID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
          localModifiedAt: Date(timeIntervalSince1970: seconds),
          sharedDeletedAt: Date(timeIntervalSince1970: seconds - 1)
        )
      ]
    )
  }
}
