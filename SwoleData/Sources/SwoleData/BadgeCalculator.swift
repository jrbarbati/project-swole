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

    // MARK: - Aggregates

    private static func finishedSessions(excluding sessionID: PersistentIdentifier?, in context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.finishedAt != nil && (sessionID == nil || $0.persistentModelID != sessionID) }
    }

    private static func exerciseVolumesLb(from sessions: [WorkoutSession]) -> [String: Double] {
        var result: [String: Double] = [:]
        for session in sessions {
            for log in session.exerciseLogs {
                result[log.exercise?.name ?? "", default: 0] += log.volume
            }
        }
        return result
    }

    // MARK: - Unlock dates (chronological pass)

    private struct UnlockDates {
        var exercise: [String: [Date?]] = [:]
        var totalVolume: [Int: Date] = [:]
        var workoutCount: [Date?] = Array(repeating: nil, count: BadgeCalculator.workoutCountTiers.count)
        var streak: [Int: Date] = [:]
    }

    private static func computeUnlockDates(sessions: [WorkoutSession], unit: MeasurementUnit, calendar: Calendar) -> UnlockDates {
        var dates = UnlockDates()
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        let exerciseTiers = exerciseVolumeTiers(unit: unit)

        var runningVolume: [String: Double] = [:]
        var runningTotal: Double = 0
        var runningCount = 0

        for session in sorted {
            let date = session.finishedAt ?? session.startedAt
            runningCount += 1
            for (index, tier) in workoutCountTiers.enumerated()
            where dates.workoutCount[index] == nil && runningCount >= tier {
                dates.workoutCount[index] = date
            }

            var sessionVolumeByExercise: [String: Double] = [:]
            for log in session.exerciseLogs {
                sessionVolumeByExercise[log.exercise?.name ?? "", default: 0] += log.volume
            }

            for (name, volume) in sessionVolumeByExercise {
                runningVolume[name, default: 0] += volume
                runningTotal += volume

                let convertedExerciseVolume = unit.fromLb(runningVolume[name] ?? 0)
                var exerciseDates = dates.exercise[name] ?? Array(repeating: nil, count: exerciseTiers.count)
                for (index, tier) in exerciseTiers.enumerated()
                where exerciseDates[index] == nil && convertedExerciseVolume >= tier {
                    exerciseDates[index] = date
                }
                dates.exercise[name] = exerciseDates
            }

            let convertedTotal = unit.fromLb(runningTotal)
            var index = 0
            while totalVolumeTier(atIndex: index, unit: unit) <= convertedTotal {
                if dates.totalVolume[index] == nil { dates.totalVolume[index] = date }
                index += 1
            }
        }

        for run in StatsCalculator.qualifyingWeeklyRuns(from: sessions, calendar: calendar)
        where streakWeekTiers.contains(run.runLength) && dates.streak[run.runLength] == nil {
            dates.streak[run.runLength] = run.sessionsInWeek.map(\.startedAt).max() ?? run.weekStart
        }

        return dates
    }

    // MARK: - Badge construction

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private static func exerciseVolumeBadge(exercise: String, index: Int, unit: MeasurementUnit, current: Double, unlocked: Bool, unlockedAt: Date?) -> Badge {
        let target = exerciseVolumeTiers(unit: unit)[index]
        return Badge(
            id: "volume.\(exercise).\(index)",
            category: .exerciseVolume(exerciseName: exercise),
            title: "\(exercise) — \(formatted(target)) \(unit.rawValue) Lifted",
            iconName: "dumbbell.fill",
            isUnlocked: unlocked,
            unlockedAt: unlockedAt,
            progressCurrent: current,
            progressTarget: target
        )
    }

    private static func totalVolumeBadge(index: Int, unit: MeasurementUnit, current: Double, unlocked: Bool, unlockedAt: Date?) -> Badge {
        let target = totalVolumeTier(atIndex: index, unit: unit)
        return Badge(
            id: "totalVolume.\(index)",
            category: .totalVolume,
            title: "\(formatted(target)) \(unit.rawValue) Total Lifted",
            iconName: "scalemass.fill",
            isUnlocked: unlocked,
            unlockedAt: unlockedAt,
            progressCurrent: current,
            progressTarget: target
        )
    }

    private static func workoutCountBadge(index: Int, current: Int, unlocked: Bool, unlockedAt: Date?) -> Badge {
        let target = workoutCountTiers[index]
        return Badge(
            id: "workoutCount.\(index)",
            category: .workoutCount,
            title: "\(target) Workouts Completed",
            iconName: "checkmark.seal.fill",
            isUnlocked: unlocked,
            unlockedAt: unlockedAt,
            progressCurrent: Double(current),
            progressTarget: Double(target)
        )
    }

    private static func streakBadge(index: Int, current: Int, unlocked: Bool, unlockedAt: Date?) -> Badge {
        let target = streakWeekTiers[index]
        return Badge(
            id: "streak.\(index)",
            category: .streak,
            title: "\(target)-Week Streak",
            iconName: "flame.fill",
            isUnlocked: unlocked,
            unlockedAt: unlockedAt,
            progressCurrent: Double(current),
            progressTarget: Double(target)
        )
    }

    // MARK: - Public API

    private static func coreBadges(unit: MeasurementUnit, excluding sessionID: PersistentIdentifier?, in context: ModelContext, now: Date, calendar: Calendar) throws -> [Badge] {
        let exercises = try context.fetch(FetchDescriptor<Exercise>()).sorted { $0.name < $1.name }
        let sessions = try finishedSessions(excluding: sessionID, in: context)
        let volumesLb = exerciseVolumesLb(from: sessions)
        let totalVolumeLb = volumesLb.values.reduce(0, +)
        let workoutCount = sessions.count
        let longestStreakWeeks = StatsCalculator.streaks(from: sessions, now: now, calendar: calendar).longestWeeks
        let unlockDates = computeUnlockDates(sessions: sessions, unit: unit, calendar: calendar)

        var badges: [Badge] = []

        let exerciseTiers = exerciseVolumeTiers(unit: unit)
        for exercise in exercises {
            let currentLb = volumesLb[exercise.name] ?? 0
            let current = unit.fromLb(currentLb)
            for (index, tier) in exerciseTiers.enumerated() {
                let unlocked = current >= tier
                badges.append(exerciseVolumeBadge(
                    exercise: exercise.name, index: index, unit: unit, current: current,
                    unlocked: unlocked, unlockedAt: unlocked ? (unlockDates.exercise[exercise.name]?[index]) : nil
                ))
            }
        }

        let totalCurrent = unit.fromLb(totalVolumeLb)
        let (totalEarned, totalNext) = totalVolumeIndices(reaching: totalCurrent, unit: unit)
        for index in totalEarned {
            badges.append(totalVolumeBadge(index: index, unit: unit, current: totalCurrent, unlocked: true, unlockedAt: unlockDates.totalVolume[index]))
        }
        badges.append(totalVolumeBadge(index: totalNext, unit: unit, current: totalCurrent, unlocked: false, unlockedAt: nil))

        for (index, tier) in workoutCountTiers.enumerated() {
            let unlocked = workoutCount >= tier
            badges.append(workoutCountBadge(index: index, current: workoutCount, unlocked: unlocked, unlockedAt: unlocked ? unlockDates.workoutCount[index] : nil))
        }

        for (index, tier) in streakWeekTiers.enumerated() {
            let unlocked = longestStreakWeeks >= tier
            badges.append(streakBadge(index: index, current: longestStreakWeeks, unlocked: unlocked, unlockedAt: unlocked ? unlockDates.streak[tier] : nil))
        }

        return badges
    }

    public static func allBadges(unit: MeasurementUnit, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws -> [Badge] {
        try coreBadges(unit: unit, excluding: nil, in: context, now: now, calendar: calendar)
    }

    public static func newlyUnlocked(for session: WorkoutSession, unit: MeasurementUnit, in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws -> [Badge] {
        let after = try coreBadges(unit: unit, excluding: nil, in: context, now: now, calendar: calendar)
        let before = try coreBadges(unit: unit, excluding: session.persistentModelID, in: context, now: now, calendar: calendar)
        let beforeUnlockedIDs = Set(before.filter(\.isUnlocked).map(\.id))
        return after.filter { $0.isUnlocked && !beforeUnlockedIDs.contains($0.id) }
    }
}
