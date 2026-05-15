//
//  CloudKitReadinessTests.swift
//  yaHerd
//
//  Created by mm on 5/15/26.
//


import XCTest
import SwiftData
@testable import yaHerd

final class CloudKitReadinessTests: XCTestCase {
    func testSwiftDataSchemaCanCreateCloudKitBackedContainer() throws {
        let schema = yaHerdApp.makeSchema()
        
        let configuration = ModelConfiguration(
            "yaHerdCloudKitReadinessStore",
            schema: schema,
            cloudKitDatabase: .automatic
        )
        
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        
        XCTAssertNotNil(container)
    }
}
