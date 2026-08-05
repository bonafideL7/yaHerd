//
//  SyncDiagnosticsRepository.swift
//  yaHerd
//

import Foundation

@MainActor
protocol SyncDiagnosticsRepository: AnyObject {
    var publicIDRepairService: any PublicIDRepairService { get }

    func fetchCounts() throws -> SyncDiagnosticsCounts
}
