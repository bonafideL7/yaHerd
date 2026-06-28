import XCTest
@testable import yaHerd

final class PastureMetricsAndPolicyTests: XCTestCase {
    func testMetricsPreferUsableAcreageOverTotalAcreage() {
        let metrics = PastureMetrics(acreage: 20, usableAcreage: 12, activeAnimals: 6, targetAcresPerHead: 2)

        XCTAssertEqual(metrics.acres, 12)
        XCTAssertEqual(metrics.acresPerHead, 2)
        XCTAssertEqual(metrics.capacityHead, 6)
        XCTAssertEqual(metrics.utilizationPercent, 1)
    }

    func testCapacityFallsBackWhenTargetAcresPerHeadIsMissing() {
        let metrics = PastureMetrics(
            acreage: nil,
            usableAcreage: nil,
            activeAnimals: 4,
            targetAcresPerHead: nil,
            fallbackCapacityHead: 8
        )

        XCTAssertEqual(metrics.capacityHead, 8)
        XCTAssertEqual(metrics.utilizationPercent, 0.5)
        XCTAssertFalse(metrics.isOverCapacity)
    }

    func testOverCapacityUsesActiveAnimalsGreaterThanCapacity() {
        let metrics = PastureMetrics(acreage: 10, usableAcreage: nil, activeAnimals: 6, targetAcresPerHead: 2)

        XCTAssertEqual(metrics.capacityHead, 5)
        XCTAssertTrue(metrics.isOverCapacity)
        XCTAssertEqual(metrics.utilizationStatus, .overCapacity)
    }

    func testUtilizationStatusThresholds() {
        XCTAssertEqual(
            PastureStockingPolicy.status(utilizationPercent: nil, isOverCapacity: false),
            .missingData
        )
        XCTAssertEqual(
            PastureStockingPolicy.status(utilizationPercent: 0.39, isOverCapacity: false),
            .underutilized
        )
        XCTAssertEqual(
            PastureStockingPolicy.status(utilizationPercent: 0.40, isOverCapacity: false),
            .normal
        )
        XCTAssertEqual(
            PastureStockingPolicy.status(utilizationPercent: 0.75, isOverCapacity: false),
            .warning
        )
        XCTAssertEqual(
            PastureStockingPolicy.status(utilizationPercent: 0.90, isOverCapacity: false),
            .danger
        )
        XCTAssertEqual(
            PastureStockingPolicy.status(utilizationPercent: 0.20, isOverCapacity: true),
            .overCapacity
        )
    }

    func testShouldUseStockingFieldsOnlyWhenAcreageExceedsMinimum() {
        XCTAssertFalse(PastureStockingPolicy.shouldUseStockingFields(acreage: nil))
        XCTAssertFalse(PastureStockingPolicy.shouldUseStockingFields(acreage: 1.0))
        XCTAssertTrue(PastureStockingPolicy.shouldUseStockingFields(acreage: 1.01))
    }

    func testRotationReadyRequiresRestedNotOverCapacityAndLowUtilization() {
        XCTAssertTrue(
            PastureStockingPolicy.isRotationReady(
                isRestedForRotation: true,
                isOverCapacity: false,
                utilizationPercent: 0.79,
                activeAnimalCount: 2
            )
        )
        XCTAssertFalse(
            PastureStockingPolicy.isRotationReady(
                isRestedForRotation: true,
                isOverCapacity: false,
                utilizationPercent: 0.80,
                activeAnimalCount: 2
            )
        )
        XCTAssertFalse(
            PastureStockingPolicy.isRotationReady(
                isRestedForRotation: false,
                isOverCapacity: false,
                utilizationPercent: 0.20,
                activeAnimalCount: 0
            )
        )
        XCTAssertFalse(
            PastureStockingPolicy.isRotationReady(
                isRestedForRotation: true,
                isOverCapacity: true,
                utilizationPercent: 0.20,
                activeAnimalCount: 0
            )
        )
    }

    func testRotationReadyWithMissingUtilizationRequiresNoActiveAnimals() {
        XCTAssertTrue(
            PastureStockingPolicy.isRotationReady(
                isRestedForRotation: true,
                isOverCapacity: false,
                utilizationPercent: nil,
                activeAnimalCount: 0
            )
        )
        XCTAssertFalse(
            PastureStockingPolicy.isRotationReady(
                isRestedForRotation: true,
                isOverCapacity: false,
                utilizationPercent: nil,
                activeAnimalCount: 1
            )
        )
    }
}
