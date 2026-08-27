import Foundation
import SwiftData

public enum WorkoutSessionServiceError: Error {
    case missingUserSettings
}

public enum WorkoutSessionService {
    public static func activeSession(in context: ModelContext) throws -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.finishedAt == nil }
        )
        descriptor.sortBy = [SortDescriptor(\.startedAt, order: .reverse)]
        return try context.fetch(descriptor).first
    }

    @discardableResult
    public static func startWorkout(in context: ModelContext) throws -> WorkoutSession {
        let settingsList = try context.fetch(FetchDescriptor<UserSettings>())
        guard let settings = settingsList.first else {
            throw WorkoutSessionServiceError.missingUserSettings
        }
        let workoutType = WorkoutScheduler.nextWorkoutType(after: settings)

        let allTemplateEntries = try context.fetch(FetchDescriptor<WorkoutTemplateExercise>())
        let entries = allTemplateEntries
            .filter { $0.workoutType == workoutType }
            .sorted { $0.order < $1.order }

        let configs = try context.fetch(FetchDescriptor<UserExerciseConfig>())

        let session = WorkoutSession(startedAt: .now, workoutType: workoutType)
        context.insert(session)

        for entry in entries {
            guard let exercise = entry.exercise else { continue }
            guard let config = configs.first(where: { $0.exercise?.persistentModelID == exercise.persistentModelID }) else {
                continue
            }

            let targetWeight = try ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: context)
            let log = ExerciseLog(
                session: session,
                exercise: exercise,
                targetWeight: targetWeight,
                targetReps: config.repsPerSet,
                order: entry.order
            )
            context.insert(log)

            for setNumber in 1...config.setCount {
                context.insert(SetLog(exerciseLog: log, setNumber: setNumber, repsCompleted: nil))
            }
        }

        try context.save()
        return session
    }
}
