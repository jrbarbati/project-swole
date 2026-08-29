//
//  WarmupPlanner.swift
//  SwoleData
//
//  Warmup sets themselves are always derived, never stored. Completion is
//  persisted separately, on ExerciseLog.completedWarmupIDs.
//

import Foundation

public struct WarmupSet: Identifiable, Equatable, Sendable {
    public let id: Int
    public let weight: Double
    public let reps: Int
}

public enum WarmupPlanner {
    /// Ramp to the working weight: empty bar, then ~55% / ~75% / ~90%,
    /// each rounded down to the smallest loadable increment, duplicates dropped.
    /// Light working weights simply produce fewer steps.
    public static func plan(
        workingWeight: Double,
        barWeight: Double = 45,
        increment: Double = 5
    ) -> [WarmupSet] {
        guard workingWeight > barWeight else { return [] }

        let ramp: [(fraction: Double, reps: Int)] = [
            (0.00, 5),
            (0.55, 5),
            (0.75, 3),
            (0.90, 2),
        ]

        var usedWeights = Set<Double>()
        var warmups: [WarmupSet] = []

        for (fraction, reps) in ramp {
            let rampWeight = barWeight + (workingWeight - barWeight) * fraction
            let loadableWeight = max(barWeight, (rampWeight / increment).rounded(.down) * increment)
            guard loadableWeight < workingWeight, !usedWeights.contains(loadableWeight) else { continue }
            usedWeights.insert(loadableWeight)
            warmups.append(WarmupSet(id: warmups.count, weight: loadableWeight, reps: reps))
        }

        return warmups
    }
}
