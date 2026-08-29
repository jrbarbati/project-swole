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

        try awardXP(for: session, in: context)

        try context.save()
    }

    private static func awardXP(for session: WorkoutSession, in context: ModelContext) throws {
        guard let state = try context.fetch(FetchDescriptor<GamificationState>()).first else { return }

        var xp = XPCalculator.workoutXP
        xp += try newPRCount(for: session, in: context) * XPCalculator.prBonusXP
        if try isThirdFinishedWorkoutThisWeek(session, in: context) {
            xp += XPCalculator.weeklyBonusXP
        }

        state.totalXP += xp
    }

    private static func newPRCount(for session: WorkoutSession, in context: ModelContext) throws -> Int {
        var count = 0
        for log in session.exerciseLogs {
            guard log.succeeded, let exercise = log.exercise else { continue }
            guard let priorBest = try StatsCalculator.priorSucceededMaxWeight(for: exercise, before: session, in: context) else { continue }
            if log.targetWeight > priorBest {
                count += 1
            }
        }
        return count
    }

    private static func isThirdFinishedWorkoutThisWeek(_ session: WorkoutSession, in context: ModelContext, calendar: Calendar = .current) throws -> Bool {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: session.startedAt) else { return false }
        let sessionID = session.persistentModelID
        let otherFinishedThisWeek = try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter {
                $0.persistentModelID != sessionID
                    && $0.finishedAt != nil
                    && weekInterval.contains($0.startedAt)
            }
        return otherFinishedThisWeek.count == 2
    }

    public static func cancelWorkout(_ session: WorkoutSession, in context: ModelContext) throws {
        context.delete(session)
        try context.save()
    }
}
