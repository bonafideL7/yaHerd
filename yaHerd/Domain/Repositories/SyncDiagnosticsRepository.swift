//
//  SyncDiagnosticsRepository.swift
//  yaHerd
//

import Foundation

@MainActor
protocol SyncDiagnosticsRepository: AnyObject {
    func fetchCounts() throws -> SyncDiagnosticsCounts
}
