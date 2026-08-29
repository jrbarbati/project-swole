import Testing
import SwiftData
import Foundation
@testable import SwoleData

private func makeSquatConfig(for squat: Exercise, in context: ModelContext) -> UserExerciseConfig {
    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: 5, deloadThreshold: 3, deloadPercentage: 0.10
    )
    context.insert(config)
    return config
}

@discardableResult
private func insertSession(
    for exercise: Exercise,
    on date: Date = Date(),
    weight: Double,
    lastSetReps: Int,
    in context: ModelContext
) -> ExerciseLog {
    let session = WorkoutSession(startedAt: date, workoutType: .a)
    context.insert(session)

    let log = ExerciseLog(session: session, exercise: exercise, targetWeight: weight, targetReps: 5)
    context.insert(log)
    for n in 1...5 {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: n == 5 ? lastSetReps : 5))
    }
    return log
}

@Test func nextTargetWeightWithNoHistoryUsesStartingWeight() throws {
    let context = try makeInMemoryContext()

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = makeSquatConfig(for: squat, in: context)
    try context.save()

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 45)
}

@Test func nextTargetWeightIncrementsAfterASuccessfulSession() throws {
    let context = try makeInMemoryContext()

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = makeSquatConfig(for: squat, in: context)

    insertSession(for: squat, weight: 135, lastSetReps: 5, in: context)
    try context.save()

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 140)
}

@Test func nextTargetWeightRepeatsAfterASingleFailure() throws {
    let context = try makeInMemoryContext()

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = makeSquatConfig(for: squat, in: context)

    insertSession(for: squat, weight: 200, lastSetReps: 3, in: context)
    try context.save()

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 200)
}

@Test func nextTargetWeightDeloadsAfterThreeConsecutiveFailures() throws {
    let context = try makeInMemoryContext()

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = makeSquatConfig(for: squat, in: context)

    let calendar = Calendar.current
    for dayOffset in 0..<3 {
        let date = calendar.date(byAdding: .day, value: dayOffset, to: Date())!
        insertSession(for: squat, on: date, weight: 200, lastSetReps: 3, in: context)
    }
    try context.save()

    let streak = try ProgressionCalculator.currentFailStreak(for: squat, in: context)
    #expect(streak == 3)

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 180)
}

@Test func failStreakResetsAfterADeload() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)

    let calendar = Calendar.current
    for (dayOffset, weight) in [200.0, 200.0, 200.0, 180.0].enumerated() {
        let date = calendar.date(byAdding: .day, value: dayOffset, to: Date())!
        insertSession(for: squat, on: date, weight: weight, lastSetReps: 3, in: context)
    }
    try context.save()

    let streak = try ProgressionCalculator.currentFailStreak(for: squat, in: context)
    #expect(streak == 1)

    let config = makeSquatConfig(for: squat, in: context)
    try context.save()

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 180)
}

@Test func nextTargetWeightUsesOverrideRegardlessOfHistory() throws {
    let context = try makeInMemoryContext()

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = makeSquatConfig(for: squat, in: context)

    insertSession(for: squat, weight: 135, lastSetReps: 5, in: context)
    try context.save()

    // Without an override, history says 140 (135 + increment, last session succeeded).
    config.weightOverride = 225
    try context.save()

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 225)
}
