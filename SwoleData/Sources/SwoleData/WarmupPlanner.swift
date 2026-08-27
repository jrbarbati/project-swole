//
//  WarmupPlanner.swift
//  SwoleData
//
//  New in the redesign. Warmups are derived, never stored — they exist only
//  as checkboxes in the exercise sheet, so nothing needs to persist unless
//  you later decide warmup completion should survive app relaunch.
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

        var seen = Set<Double>()
        var result: [WarmupSet] = []

        for (fraction, reps) in ramp {
            let raw = barWeight + (workingWeight - barWeight) * fraction
            let rounded = max(barWeight, (raw / increment).rounded(.down) * increment)
            guard rounded < workingWeight, !seen.contains(rounded) else { continue }
            seen.insert(rounded)
            result.append(WarmupSet(id: result.count, weight: rounded, reps: reps))
        }

        return result
    }
}
