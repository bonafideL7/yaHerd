//
//  HerdSharingBridgeStep.swift
//  yaHerd
//

import Foundation

enum HerdSharingBridgeDirection: String, Codable, Equatable {
  case exportToBridge
  case importFromBridge
}

enum HerdSharingBridgeStep: String, CaseIterable, Codable, Equatable, Hashable {
  case herd
  case tagColorDefinitions
  case statusReferences
  case pastureGroups
  case pastures
  case animals
  case animalTags
  case movements
  case statusRecords
  case workingProtocolTemplates
  case workingSessions
  case workingQueueItems
  case workingTreatmentRecords
  case healthRecords
  case pregnancyChecks
  case fieldCheckSessions
  case fieldCheckAnimalChecks
  case fieldCheckFindings
  case deletions
  case persistentStoreCommit
  case cloudKitShareUpdate
  case reconciliation

  static let entitySteps: [HerdSharingBridgeStep] = [
    .herd,
    .tagColorDefinitions,
    .statusReferences,
    .pastureGroups,
    .pastures,
    .animals,
    .animalTags,
    .movements,
    .statusRecords,
    .workingProtocolTemplates,
    .workingSessions,
    .workingQueueItems,
    .workingTreatmentRecords,
    .healthRecords,
    .pregnancyChecks,
    .fieldCheckSessions,
    .fieldCheckAnimalChecks,
    .fieldCheckFindings,
    .deletions,
  ]

  var displayName: String {
    switch self {
    case .herd: "Herd"
    case .tagColorDefinitions: "Tag color definitions"
    case .statusReferences: "Status references"
    case .pastureGroups: "Pasture groups"
    case .pastures: "Pastures"
    case .animals: "Animals"
    case .animalTags: "Animal tags"
    case .movements: "Movements"
    case .statusRecords: "Status records"
    case .workingProtocolTemplates: "Working protocol templates"
    case .workingSessions: "Working sessions"
    case .workingQueueItems: "Working queue items"
    case .workingTreatmentRecords: "Working treatment records"
    case .healthRecords: "Health records"
    case .pregnancyChecks: "Pregnancy checks"
    case .fieldCheckSessions: "Field check sessions"
    case .fieldCheckAnimalChecks: "Field check animal checks"
    case .fieldCheckFindings: "Field check findings"
    case .deletions: "Deletion tombstones"
    case .persistentStoreCommit: "Persistent-store commit"
    case .cloudKitShareUpdate: "CloudKit share update"
    case .reconciliation: "Reconciliation"
    }
  }
}

struct HerdSharingBridgeFailureInjector {
  static let disabled = HerdSharingBridgeFailureInjector { _ in nil }

  private let injectedError: (HerdSharingBridgeStep) -> Error?

  init(_ injectedError: @escaping (HerdSharingBridgeStep) -> Error?) {
    self.injectedError = injectedError
  }

  func check(after step: HerdSharingBridgeStep) throws {
    if let error = injectedError(step) {
      throw error
    }
  }
}
