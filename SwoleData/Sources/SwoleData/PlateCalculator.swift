//
//  PlateCalculator.swift
//  SwoleData
//
//  New in the redesign. Plate math is shown on every exercise card, so it
//  belongs in the package (pure, testable) rather than in a view.
//

import Foundation

public struct PlateMath: Equatable, Sendable {
    /// Plates for ONE side of the bar, heaviest first.
    public let perSide: [Double]
    /// Weight that could not be made with the available plates.
    public let remainder: Double
    public let barWeight: Double

    public var isExact: Bool { remainder == 0 }

    /// "45 · 2.5" — what the exercise card shows next to the target weight.
    public var shortDescription: String {
        guard !perSide.isEmpty else { return "BAR ONLY" }
        return perSide.map { $0.formatted(.number.precision(.fractionLength(0...1))) }
            .joined(separator: " · ")
    }
}

public enum PlateCalculator {
    /// Standard iron, heaviest first.
    public static let lbPlates: [Double] = [45, 35, 25, 10, 5, 2.5]
    public static let kgPlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    public static func plates(
        for target: Double,
        barWeight: Double = 45,
        available: [Double] = lbPlates
    ) -> PlateMath {
        guard target > barWeight else {
            return PlateMath(perSide: [], remainder: 0, barWeight: barWeight)
        }

        var remainingPerSide = (target - barWeight) / 2
        var picked: [Double] = []

        for plate in available.sorted(by: >) {
            while remainingPerSide + 0.001 >= plate {
                picked.append(plate)
                remainingPerSide -= plate
            }
        }

        let remainder = remainingPerSide < 0.001 ? 0 : remainingPerSide * 2
        return PlateMath(perSide: picked, remainder: remainder, barWeight: barWeight)
    }

    public static func barWeight(for unit: MeasurementUnit) -> Double {
        unit == .lb ? 45 : 20
    }

    public static func plateSet(for unit: MeasurementUnit) -> [Double] {
        unit == .lb ? lbPlates : kgPlates
    }
}
