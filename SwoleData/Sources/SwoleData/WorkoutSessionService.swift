import Foundation
import SwiftData

public enum WorkoutSessionServiceError: Error {
    case missingUserSettings
}

public enum WorkoutSessionService {
    public static func activeSession(in context: ModelContext) throws -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.finishedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    @discardableResult
    public static func startWorkout(
        in context: ModelContext,
        weightOverrides: [PersistentIdentifier: Double] = [:]
    ) throws -> WorkoutSession {
        guard let settings = try context.fetch(FetchDescriptor<UserSettings>()).first else {
            throw WorkoutSessionServiceError.missingUserSettings
        }
        let workoutType = WorkoutScheduler.nextWorkoutType(after: settings)

        let allTemplateEntries = try context.fetch(FetchDescriptor<WorkoutTemplateExercise>())
        let entriesForWorkout = allTemplateEntries
            .filter { $0.workoutType == workoutType }
            .sorted { $0.order < $1.order }

        let configs = try context.fetch(FetchDescriptor<UserExerciseConfig>())

        let session = WorkoutSession(startedAt: .now, workoutType: workoutType)
        context.insert(session)

        for entry in entriesForWorkout {
            guard let exercise = entry.exercise,
                  let config = configs.first(where: { $0.exercise?.persistentModelID == exercise.persistentModelID })
            else { continue }

            try insertExerciseLog(
                for: exercise,
                config: config,
                order: entry.order,
                in: session,
                weightOverride: weightOverrides[exercise.persistentModelID],
                context: context
            )
        }

        try context.save()
        return session
    }

    private static func insertExerciseLog(
        for exercise: Exercise,
        config: UserExerciseConfig,
        order: Int,
        in session: WorkoutSession,
        weightOverride: Double?,
        context: ModelContext
    ) throws {
        let targetWeight = try weightOverride
            ?? ProgressionCalculator.nextTargetWeight(for: exercise, config: config, in: context)
        config.weightOverride = nil
        let log = ExerciseLog(
            session: session,
            exercise: exercise,
            targetWeight: targetWeight,
            targetReps: config.repsPerSet,
            order: order
        )
        context.insert(log)

        for setNumber in 1...config.setCount {
            context.insert(SetLog(exerciseLog: log, setNumber: setNumber, repsCompleted: nil))
        }
    }

    public static func finishWorkout(_ session: WorkoutSession, in context: ModelContext) throws {
        for log in session.exerciseLogs {
            for set in log.sets where set.repsCompleted == nil {
                set.repsCompleted = 0
            }
        }
        session.finishedAt = .now

        let allSettings = try context.fetch(FetchDescriptor<UserSettings>())
        allSettings.first?.lastCompletedWorkoutType = session.workoutType

        try context.save()
    }

    public static func cancelWorkout(_ session: WorkoutSession, in context: ModelContext) throws {
        context.delete(session)
        try context.save()
    }
}
