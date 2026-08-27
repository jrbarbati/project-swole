import Foundation
import SwiftData

public extension ProgressionCalculator {

    /// Logs for one exercise, oldest → newest, capped at `limit`.
    /// Chart-friendly order.
    static func recentLogs(for exercise: Exercise, limit: Int, in context: ModelContext) throws -> [ExerciseLog] {
        let exerciseID = exercise.persistentModelID
        let allLogs = try context.fetch(FetchDescriptor<ExerciseLog>())

        return allLogs
            .filter { $0.exercise?.persistentModelID == exerciseID }
            .filter { $0.session?.finishedAt != nil }
            .sorted { ($0.session?.startedAt ?? .distantPast) < ($1.session?.startedAt ?? .distantPast) }
            .suffix(limit)
    }

    /// The most recent finished log for this exercise before `log`.
    /// Used for the "LAST 130 · 5 5 5 5 5" line on the exercise card.
    static func previousLog(for exercise: Exercise, before log: ExerciseLog) throws -> ExerciseLog? {
        guard let context = log.modelContext else {
            return nil
        }

        let cutoff = log.session?.startedAt ?? .now
        let exerciseID = exercise.persistentModelID
        let allLogs = try context.fetch(FetchDescriptor<ExerciseLog>())

        return allLogs
            .filter { $0.exercise?.persistentModelID == exerciseID }
            .filter { $0.session?.finishedAt != nil }
            .filter { ($0.session?.startedAt ?? .distantPast) < cutoff }
            .max { ($0.session?.startedAt ?? .distantPast) < ($1.session?.startedAt ?? .distantPast) }
    }
}
