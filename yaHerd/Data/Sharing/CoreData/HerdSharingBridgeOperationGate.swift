//
//  HerdSharingBridgeOperationGate.swift
//  yaHerd
//

import Foundation

/// Serializes repository-level bridge mutations across suspension points.
///
/// The Core Data bridge and SwiftData context form one logical synchronization boundary. Allowing
/// two imports, exports, restorations, or invitation flows to interleave can reorder snapshots and
/// make a later operation commit state captured before an earlier operation completed.
@MainActor
final class HerdSharingBridgeOperationGate {
  private var isOperationActive = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func acquire() async {
    guard isOperationActive else {
      isOperationActive = true
      return
    }

    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func release() {
    guard !waiters.isEmpty else {
      isOperationActive = false
      return
    }

    let next = waiters.removeFirst()
    next.resume()
  }
}
