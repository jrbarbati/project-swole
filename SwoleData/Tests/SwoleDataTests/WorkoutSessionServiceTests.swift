import Testing
import SwiftData
import Foundation
@testable import SwoleData

private func makeSeededContext() throws -> ModelContext {
    let context = try makeInMemoryContext()
    _ = try StandardSeed.seed(in: context)
    return context
}

@Test func activeSessionIsNilWhenNoneExists() throws {
    let context = try makeSeededContext()
    #expect(try WorkoutSessionService.activeSession(in: context) == nil)
}

@Test func startWorkoutCreatesExerciseLogsInTemplateOrderWithComputedWeights() throws {
    let context = try makeSeededContext()

    let session = try WorkoutSessionService.startWorkout(in: context)

    #expect(session.workoutType == .a)
    #expect(session.finishedAt == nil)

    let logs = session.exerciseLogs.sorted { $0.order < $1.order }
    #expect(logs.map { $0.exercise?.name } == ["Squat", "Bench Press", "Barbell Row"])
    #expect(logs.map(\.order) == [0, 1, 2])

    let squatLog = logs[0]
    #expect(squatLog.targetWeight == 45)
    #expect(squatLog.targetReps == 5)
    #expect(squatLog.sets.count == 5)
    #expect(squatLog.sets.allSatisfy { $0.repsCompleted == nil })

    #expect(try WorkoutSessionService.activeSession(in: context) === session)
}

@Test func startWorkoutThrowsWhenUserSettingsAreMissing() throws {
    let context = try makeInMemoryContext()
    #expect(throws: WorkoutSessionServiceError.self) {
        try WorkoutSessionService.startWorkout(in: context)
    }
}

@Test func finishWorkoutCoercesUnsetRepsToZeroLocksSessionAndUpdatesSettings() throws {
    let context = try makeSeededContext()
    let session = try WorkoutSessionService.startWorkout(in: context)

    try WorkoutSessionService.finishWorkout(session, in: context)

    #expect(session.finishedAt != nil)
    #expect(session.exerciseLogs.flatMap(\.sets).allSatisfy { $0.repsCompleted == 0 })

    let settings = try context.fetch(FetchDescriptor<UserSettings>()).first
    #expect(settings?.lastCompletedWorkoutType == .a)
    #expect(try WorkoutSessionService.activeSession(in: context) == nil)
}

@Test func cancelWorkoutDeletesSessionAndLeavesLastCompletedWorkoutTypeUntouched() throws {
    let context = try makeSeededContext()
    let session = try WorkoutSessionService.startWorkout(in: context)

    try WorkoutSessionService.cancelWorkout(session, in: context)

    #expect(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<ExerciseLog>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)

    let settings = try context.fetch(FetchDescriptor<UserSettings>()).first
    #expect(settings?.lastCompletedWorkoutType == nil)
}

@Test func startWorkoutConsumesWeightOverrideIntoTheLogAndClearsIt() throws {
    let context = try makeSeededContext()

    let squat = try context.fetch(FetchDescriptor<Exercise>())
        .first { $0.name == "Squat" }
    let config = try context.fetch(FetchDescriptor<UserExerciseConfig>())
        .first { $0.exercise?.persistentModelID == squat?.persistentModelID }
    config?.weightOverride = 225
    try context.save()

    let session = try WorkoutSessionService.startWorkout(in: context)

    let squatLog = session.exerciseLogs.first { $0.exercise?.name == "Squat" }
    #expect(squatLog?.targetWeight == 225)
    #expect(config?.weightOverride == nil)
}

@Test func startWorkoutPrefersAnExplicitWeightOverrideOverConfigAndComputedWeight() throws {
    let context = try makeSeededContext()

    let squat = try context.fetch(FetchDescriptor<Exercise>())
        .first { $0.name == "Squat" }
    let config = try context.fetch(FetchDescriptor<UserExerciseConfig>())
        .first { $0.exercise?.persistentModelID == squat?.persistentModelID }
    config?.weightOverride = 225
    try context.save()

    let session = try WorkoutSessionService.startWorkout(
        in: context,
        weightOverrides: [squat!.persistentModelID: 250]
    )

    let squatLog = session.exerciseLogs.first { $0.exercise?.name == "Squat" }
    #expect(squatLog?.targetWeight == 250)
    #expect(config?.weightOverride == nil)
}

// MARK: - XP awards

@Test func finishWorkoutAwardsBaseXPOnlyWithNoPRsAndNotTheThirdWorkoutOfTheWeek() throws {
    let context = try makeSeededContext()
    let session = try WorkoutSessionService.startWorkout(in: context)

    try WorkoutSessionService.finishWorkout(session, in: context)

    let state = try context.fetch(FetchDescriptor<GamificationState>()).first
    #expect(state?.totalXP == XPCalculator.workoutXP)
}

@Test func finishWorkoutAwardsXPPerNewPRExerciseInTheSession() throws {
    let context = try makeSeededContext()

    let squat = try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Squat" }!
    let bench = try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Bench Press" }!

    // A prior finished session establishes a baseline for squat and bench.
    let priorStart = Date().addingTimeInterval(-7 * 24 * 3600)
    let priorSession = WorkoutSession(startedAt: priorStart, workoutType: .a, finishedAt: priorStart.addingTimeInterval(2400))
    context.insert(priorSession)
    let priorSquatLog = ExerciseLog(session: priorSession, exercise: squat, targetWeight: 135, targetReps: 5)
    context.insert(priorSquatLog)
    for n in 1...5 { context.insert(SetLog(exerciseLog: priorSquatLog, setNumber: n, repsCompleted: 5)) }
    let priorBenchLog = ExerciseLog(session: priorSession, exercise: bench, targetWeight: 95, targetReps: 5)
    context.insert(priorBenchLog)
    for n in 1...5 { context.insert(SetLog(exerciseLog: priorBenchLog, setNumber: n, repsCompleted: 5)) }

    let settings = try context.fetch(FetchDescriptor<UserSettings>()).first!
    settings.lastCompletedWorkoutType = .b
    try context.save()

    let session = try WorkoutSessionService.startWorkout(
        in: context,
        weightOverrides: [squat.persistentModelID: 185, bench.persistentModelID: 100]
    )
    for log in session.exerciseLogs where log.exercise?.name == "Squat" || log.exercise?.name == "Bench Press" {
        for set in log.sets { set.repsCompleted = log.targetReps }
    }

    try WorkoutSessionService.finishWorkout(session, in: context)

    let state = try context.fetch(FetchDescriptor<GamificationState>()).first
    #expect(state?.totalXP == XPCalculator.workoutXP + 2 * XPCalculator.prBonusXP)
}

@Test func finishWorkoutAwardsTheWeeklyBonusOnlyOnTheThirdFinishedWorkoutOfTheWeek() throws {
    let context = try makeSeededContext()
    let now = Date()
    let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: now)!.start

    for offset in [1, 2] {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: weekStart)!
        let dummy = WorkoutSession(startedAt: date, workoutType: .a, finishedAt: date.addingTimeInterval(2400))
        context.insert(dummy)
    }
    try context.save()

    let settings = try context.fetch(FetchDescriptor<UserSettings>()).first!
    settings.lastCompletedWorkoutType = .b
    try context.save()

    let thirdSession = try WorkoutSessionService.startWorkout(in: context)
    try WorkoutSessionService.finishWorkout(thirdSession, in: context)

    let stateAfterThird = try context.fetch(FetchDescriptor<GamificationState>()).first
    #expect(stateAfterThird?.totalXP == XPCalculator.workoutXP + XPCalculator.weeklyBonusXP)

    let fourthSession = try WorkoutSessionService.startWorkout(in: context)
    try WorkoutSessionService.finishWorkout(fourthSession, in: context)

    let stateAfterFourth = try context.fetch(FetchDescriptor<GamificationState>()).first
    #expect(stateAfterFourth?.totalXP == (XPCalculator.workoutXP + XPCalculator.weeklyBonusXP) + XPCalculator.workoutXP)
}
