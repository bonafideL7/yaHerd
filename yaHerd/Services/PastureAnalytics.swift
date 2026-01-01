//
//  PastureAnalytics.swift
//  yaHerd
//
//  Created by mm on 12/3/25.
//


import Foundation

struct PastureAnalytics {

    let pasture: Pasture
    let aliveAnimals: Int

    var acres: Double {
        pasture.usableAcreage ?? pasture.acreage ?? 0
    }

    var headPerAcre: Double {
        guard acres > 0 else { return 0 }
        return Double(aliveAnimals) / acres
    }

    var targetHeadPerAcre: Double? {
        pasture.targetHeadPerAcre
    }

    var capacityHead: Double? {
        guard let target = targetHeadPerAcre else { return nil }
        return acres * target
    }

    var utilizationPercent: Double? {
        guard let cap = capacityHead, cap > 0 else { return nil }
        return (Double(aliveAnimals) / cap) * 100
    }

    var isOverstocked: Bool {
        if let cap = capacityHead {
            return Double(aliveAnimals) > cap
        }
        return false
    }

    var isUnderutilized: Bool {
        if let percent = utilizationPercent {
            return percent < 40     // adjustable threshold
        }
        return false
    }
}
