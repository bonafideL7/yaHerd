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
    /// Optional fallback capacity (head count) used when `targetAcresPerHead` is not set.
    /// Intended for dashboard-level heuristics (e.g., global pasture capacity setting).
    let fallbackCapacityHead: Double?
    
    init(pasture: Pasture, aliveAnimals: Int, fallbackCapacityHead: Double? = nil) {
        self.pasture = pasture
        self.aliveAnimals = aliveAnimals
        self.fallbackCapacityHead = fallbackCapacityHead
    }
    
    var acres: Double {
        pasture.usableAcreage ?? pasture.acreage ?? 0
    }
    
    var acresPerHead: Double {
        guard acres > 0, aliveAnimals > 0 else { return 0 }
        return acres / Double(aliveAnimals)
    }
    
    var targetAcresPerHead: Double? {
        pasture.targetAcresPerHead
    }
    
    var capacityHead: Double? {
        if let target = targetAcresPerHead, target > 0, acres > 0 {
            let cap = acres / target
            return cap > 0 ? cap : nil
        }
        
        if let fallback = fallbackCapacityHead, fallback > 0 {
            return fallback
        }
        
        return nil
    }
    
    var utilizationPercent: Double? {
        guard let cap = capacityHead, cap > 0 else { return nil }
        // Fraction in [0, 1], suitable for `.percent` formatting and thresholding.
        return Double(aliveAnimals) / cap
    }
    
    var isOverstocked: Bool {
        if let cap = capacityHead {
            return Double(aliveAnimals) > cap
        }
        return false
    }
    
    var isUnderutilized: Bool {
        if let percent = utilizationPercent {
            return percent < 0.40     // adjustable threshold
        }
        return false
    }
}
