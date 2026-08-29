import Foundation
import SwiftData

public enum StatsRange: String, CaseIterable, Sendable {
    case fourWeeks, twelveWeeks, all

    var days: Int? {
        switch self {
        case .fourWeeks: return 28
        case .twelveWeeks: return 84
        case .all: return nil
        }
    }
}

public struct StatsTotals: Equatable, Sendable {
    public let workoutCount: Int
    public let totalVolume: Double
    public let averageDuration: TimeInterval
}

public struct VolumePoint: Identifiable, Equatable, Sendable {
    public var id: Date { weekStart }
    public let weekStart: Date
    public let volume: Double
}

public struct StreakInfo: Equatable, Sendable {
    public let currentWeeks: Int
    public let longestWeeks: Int
}

public struct PersonalRecord: Identifiable {
    public var id: PersistentIdentifier { exercise.persistentModelID }
    public let exercise: Exercise
    public let weight: Double
    public let reps: Int
    public let achievedAt: Date
    public let isWithinRange: Bool
}

public enum StatsCalculator {
    private static func finishedSessions(in context: ModelContext) throws -> [WorkoutSession] {
        try context.fetch(FetchDescriptor<WorkoutSession>()).filter { $0.finishedAt != nil }
    }

    private static func sessions(in range: StatsRange, now: Date, context: ModelContext) throws -> [WorkoutSession] {
        let sessions = try finishedSessions(in: context)
        guard let days = range.days else { return sessions }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? .distantPast
        return sessions.filter { $0.startedAt >= cutoff }
    }

    public static func totals(range: StatsRange, in context: ModelContext, now: Date = .now) throws -> StatsTotals {
        let sessions = try sessions(in: range, now: now, context: context)
        guard !sessions.isEmpty else {
            return StatsTotals(workoutCount: 0, totalVolume: 0, averageDuration: 0)
        }

        let totalVolume = sessions.reduce(0) { $0 + $1.volume }
        let totalDuration = sessions.reduce(0.0) { $0 + ($1.finishedAt?.timeIntervalSince($1.startedAt) ?? 0) }

        return StatsTotals(
            workoutCount: sessions.count,
            totalVolume: totalVolume,
            averageDuration: totalDuration / Double(sessions.count)
        )
    }

    public static func streaks(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) throws -> StreakInfo {
        let sessions = try finishedSessions(in: context)
        let weekStarts = Set(sessions.map { calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start ?? $0.startedAt })
        guard !weekStarts.isEmpty else { return StreakInfo(currentWeeks: 0, longestWeeks: 0) }

        let sorted = weekStarts.sorted()
        var longest = 1
        var run = 1
        for i in 1..<sorted.count {
            if calendar.date(byAdding: .day, value: 7, to: sorted[i - 1]) == sorted[i] {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
        }

        let nowWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let priorWeekStart = calendar.date(byAdding: .day, value: -7, to: nowWeekStart) ?? nowWeekStart

        var current = 0
        if weekStarts.contains(nowWeekStart) || weekStarts.contains(priorWeekStart) {
            var cursor = weekStarts.contains(nowWeekStart) ? nowWeekStart : priorWeekStart
            while weekStarts.contains(cursor) {
                current += 1
                cursor = calendar.date(byAdding: .day, value: -7, to: cursor) ?? .distantPast
            }
        }

        return StreakInfo(currentWeeks: current, longestWeeks: longest)
    }

    public static func personalRecords(
        range: StatsRange,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> [PersonalRecord] {
        let logs = try context.fetch(FetchDescriptor<ExerciseLog>())
            .filter { $0.session?.finishedAt != nil && $0.succeeded }
        let byExercise = Dictionary(grouping: logs) { $0.exercise?.persistentModelID }
        let cutoff = range.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: now) }

        return byExercise.values.compactMap { logsForExercise -> PersonalRecord? in
            guard let best = logsForExercise.max(by: { lhs, rhs in
                if lhs.targetWeight != rhs.targetWeight { return lhs.targetWeight < rhs.targetWeight }
                return (lhs.session?.startedAt ?? .distantPast) < (rhs.session?.startedAt ?? .distantPast)
            }), let exercise = best.exercise, let achievedAt = best.session?.startedAt else { return nil }

            return PersonalRecord(
                exercise: exercise,
                weight: best.targetWeight,
                reps: best.targetReps,
                achievedAt: achievedAt,
                isWithinRange: cutoff.map { achievedAt >= $0 } ?? true
            )
        }
        .sorted { $0.exercise.name < $1.exercise.name }
    }

    /// The highest `targetWeight` among other finished, successful sessions
    /// for this exercise — `nil` if there are none. Used to detect whether a
    /// session in progress of being finished just set a new PR.
    public static func priorSucceededMaxWeight(
        for exercise: Exercise,
        before session: WorkoutSession,
        in context: ModelContext
    ) throws -> Double? {
        let exerciseID = exercise.persistentModelID
        let sessionID = session.persistentModelID
        let logs = try context.fetch(FetchDescriptor<ExerciseLog>())
            .filter {
                $0.exercise?.persistentModelID == exerciseID
                    && $0.session?.persistentModelID != sessionID
                    && $0.session?.finishedAt != nil
                    && $0.succeeded
            }
        return logs.map(\.targetWeight).max()
    }

    public static func trendLogs(
        for exercise: Exercise,
        range: StatsRange,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> [ExerciseLog] {
        let exerciseID = exercise.persistentModelID
        let cutoff = range.days.flatMap { calendar.date(byAdding: .day, value: -$0, to: now) }
        let allLogs = try context.fetch(FetchDescriptor<ExerciseLog>())

        return allLogs
            .filter { $0.exercise?.persistentModelID == exerciseID }
            .filter { $0.session?.finishedAt != nil }
            .filter { log in cutoff.map { (log.session?.startedAt ?? .distantPast) >= $0 } ?? true }
            .sorted { ($0.session?.startedAt ?? .distantPast) < ($1.session?.startedAt ?? .distantPast) }
    }

    public static func weeklyVolume(
        range: StatsRange,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> [VolumePoint] {
        let sessions = try sessions(in: range, now: now, context: context)
        let byWeek = Dictionary(grouping: sessions) { session in
            calendar.dateInterval(of: .weekOfYear, for: session.startedAt)?.start ?? session.startedAt
        }

        return byWeek
            .map { weekStart, sessions in VolumePoint(weekStart: weekStart, volume: sessions.reduce(0) { $0 + $1.volume }) }
            .sorted { $0.weekStart < $1.weekStart }
    }
}
