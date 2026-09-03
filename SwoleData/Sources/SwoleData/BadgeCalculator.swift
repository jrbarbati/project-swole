import Foundation
import SwiftData

public enum BadgeCategory: Hashable, Sendable {
    case exerciseVolume(exerciseName: String)
    case totalVolume
    case workoutCount
    case streak
}

public struct Badge: Identifiable, Equatable, Sendable {
    public let id: String
    public let category: BadgeCategory
    public let title: String
    public let iconName: String
    public let isUnlocked: Bool
    public let unlockedAt: Date?
    public let progressCurrent: Double
    public let progressTarget: Double
}

public enum BadgeCalculator {

    // MARK: - Tier tables

    private static let exerciseVolumeTiersLb: [Double] = [1000, 5000, 10000, 25000, 50000, 100000]
    private static let exerciseVolumeTiersKg: [Double] = [500, 2500, 5000, 10000, 25000, 50000]

    private static let totalVolumeBaseTiersLb: [Double] = [2000, 5000, 10000, 15000, 20000]
    private static let totalVolumeStepLb: Double = 10000
    private static let totalVolumeBaseTiersKg: [Double] = [1000, 2500, 5000, 7500, 10000]
    private static let totalVolumeStepKg: Double = 5000

    static let workoutCountTiers: [Int] = [10, 25, 50, 100, 250, 500]
    static let streakWeekTiers: [Int] = [4, 12, 26, 52]

    private static func exerciseVolumeTiers(unit: MeasurementUnit) -> [Double] {
        unit == .lb ? exerciseVolumeTiersLb : exerciseVolumeTiersKg
    }

    /// Tier value at `index` (0-based) for the open-ended total-volume ladder.
    static func totalVolumeTier(atIndex index: Int, unit: MeasurementUnit) -> Double {
        let base = unit == .lb ? totalVolumeBaseTiersLb : totalVolumeBaseTiersKg
        let step = unit == .lb ? totalVolumeStepLb : totalVolumeStepKg
        if index < base.count { return base[index] }
        return base[base.count - 1] + step * Double(index - base.count + 1)
    }

    /// Every tier index whose threshold is `<= value`, plus the single next
    /// locked index — never the full infinite ladder.
    static func totalVolumeIndices(reaching value: Double, unit: MeasurementUnit) -> (earned: [Int], next: Int) {
        var earned: [Int] = []
        var index = 0
        while totalVolumeTier(atIndex: index, unit: unit) <= value {
            earned.append(index)
            index += 1
        }
        return (earned, index)
    }
}
