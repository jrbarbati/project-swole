import Foundation
import SwiftData

public enum WorkoutSessionServiceError: Error {
    case missingUserSettings
}

/// XP breakdown for a single `finishWorkout` call, for post-workout display.
public struct XPAward: Equatable {
    public let base: Int
    public let prCount: Int
    public let prBonus: Int
    public let perfectBonus: Int
    public let weeklyBonus: Int
    public let xpBefore: Int
    public let xpAfter: Int
    public let newBadges: [Badge]
    public var total: Int { base + prBonus + perfectBonus + weeklyBonus }
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

    @discardableResult
    public static func finishWorkout(_ session: WorkoutSession, in context: ModelContext) throws -> XPAward {
        for log in session.exerciseLogs {
            for set in log.sets where set.repsCompleted == nil {
                set.repsCompleted = 0
            }
        }
        session.finishedAt = .now

        let settings = try context.fetch(FetchDescriptor<UserSettings>()).first
        settings?.lastCompletedWorkoutType = session.workoutType

        let unit = settings?.unit ?? .lb
        let newBadges = try BadgeCalculator.newlyUnlocked(for: session, unit: unit, in: context)
        let award = try awardXP(for: session, newBadges: newBadges, in: context)

        try context.save()
        return award
    }

    private static func awardXP(for session: WorkoutSession, newBadges: [Badge], in context: ModelContext) throws -> XPAward {
        let state: GamificationState
        if let existing = try context.fetch(FetchDescriptor<GamificationState>()).first {
            state = existing
        } else {
            state = GamificationState(totalXP: 0)
            context.insert(state)
        }

        let xpBefore = state.totalXP
        let base = XPCalculator.workoutXP
        let prCount = try newPRCount(for: session, in: context)
        let prBonus = prCount * XPCalculator.prBonusXP
        let isPerfect = !session.exerciseLogs.isEmpty && session.exerciseLogs.allSatisfy(\.succeeded)
        let perfectBonus = isPerfect ? XPCalculator.perfectBonusXP : 0
        let weeklyBonus = try isThirdFinishedWorkoutThisWeek(session, in: context) ? XPCalculator.weeklyBonusXP : 0
        let earned = base + prBonus + perfectBonus + weeklyBonus

        let award = XPAward(
            base: base,
            prCount: prCount,
            prBonus: prBonus,
            perfectBonus: perfectBonus,
            weeklyBonus: weeklyBonus,
            xpBefore: xpBefore,
            xpAfter: xpBefore + earned,
            newBadges: newBadges
        )
        state.totalXP = award.xpAfter
        return award
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
