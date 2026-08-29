import Foundation

public enum XPCalculator {
    public static let workoutXP = 60
    public static let prBonusXP = 20
    public static let weeklyBonusXP = 120

    private static let levelCurveConstant = 50.0
    private static let levelCurveExponent = 1.5
    private static let levelCurveCap = 2500

    /// XP required to go from `level` to `level + 1`.
    public static func xpForLevel(_ level: Int) -> Int {
        let raw = levelCurveConstant * pow(Double(level), levelCurveExponent)
        return min(Int(raw.rounded()), levelCurveCap)
    }

    /// The level for a total XP amount. Level 1 starts at 0 XP.
    public static func level(forXP xp: Int) -> Int {
        progress(forXP: xp).level
    }

    /// XP earned within the current level, XP needed to complete it, and the current level.
    public static func progress(forXP xp: Int) -> (current: Int, needed: Int, level: Int) {
        var level = 1
        var remaining = xp
        while remaining >= xpForLevel(level) {
            remaining -= xpForLevel(level)
            level += 1
        }
        return (current: remaining, needed: xpForLevel(level), level: level)
    }
}
