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

    public static func currentFailStreak(for exercise: Exercise, in context: ModelContext) throws -> Int {
        let logs = try sortedLogs(for: exercise, in: context)
        var streak = 0
        for log in logs {
            if log.succeeded { break }
            streak += 1
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
