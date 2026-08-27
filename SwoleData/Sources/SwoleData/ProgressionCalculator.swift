import Foundation
import SwiftData

public enum ProgressionCalculator {
    private static func sortedLogs(for exercise: Exercise, in context: ModelContext) throws -> [ExerciseLog] {
        let exerciseID = exercise.persistentModelID
        let allLogs = try context.fetch(FetchDescriptor<ExerciseLog>())
        return allLogs
            .filter { $0.exercise?.persistentModelID == exerciseID }
            .sorted { ($0.session?.date ?? .distantPast) > ($1.session?.date ?? .distantPast) }
    }

    /// Counts consecutive fails back from the most recent log, stopping not
    /// just at the first success but also at any weight discontinuity: a
    /// fail-streak only repeats a session at the same weight (see
    /// `nextTargetWeight` below), so a change in `targetWeight` between two
    /// consecutive fails means a deload happened there, and the streak must
    /// not count fails from before that deload.
    public static func currentFailStreak(for exercise: Exercise, in context: ModelContext) throws -> Int {
        let logs = try sortedLogs(for: exercise, in: context)
        var streak = 0
        var streakWeight: Double?
        for log in logs {
            if log.succeeded { break }
            if let streakWeight, log.targetWeight != streakWeight { break }
            streak += 1
            streakWeight = log.targetWeight
        }
        return streak
    }

    public static func nextTargetWeight(
        for exercise: Exercise,
        config: UserExerciseConfig,
        in context: ModelContext
    ) throws -> Double {
        let logs = try sortedLogs(for: exercise, in: context)
        guard let lastLog = logs.first else {
            return config.startingWeight
        }
        if lastLog.succeeded {
            return lastLog.targetWeight + config.weightIncrement
        }
        let streak = try currentFailStreak(for: exercise, in: context)
        if streak >= config.deloadThreshold {
            return lastLog.targetWeight * (1 - config.deloadPercentage)
        }
        return lastLog.targetWeight
    }
}
