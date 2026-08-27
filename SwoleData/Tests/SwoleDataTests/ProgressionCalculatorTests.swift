import Testing
import SwiftData
import Foundation
@testable import SwoleData

@Test func nextTargetWeightWithNoHistoryUsesStartingWeight() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: 5, deloadThreshold: 3, deloadPercentage: 0.10
    )
    context.insert(config)
    try context.save()

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 45)
}

@Test func nextTargetWeightIncrementsAfterASuccessfulSession() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: 5, deloadThreshold: 3, deloadPercentage: 0.10
    )
    context.insert(config)
    let session = WorkoutSession(date: Date(), workoutType: .a)
    context.insert(session)
    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 135, targetReps: 5)
    context.insert(log)
    for n in 1...5 { context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: 5)) }
    try context.save()

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 140)
}

@Test func nextTargetWeightRepeatsAfterASingleFailure() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: 5, deloadThreshold: 3, deloadPercentage: 0.10
    )
    context.insert(config)
    let session = WorkoutSession(date: Date(), workoutType: .a)
    context.insert(session)
    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 200, targetReps: 5)
    context.insert(log)
    for n in 1...5 { context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: n == 5 ? 3 : 5)) }
    try context.save()

    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 200)
}

@Test func nextTargetWeightDeloadsAfterThreeConsecutiveFailures() throws {
    let context = try makeInMemoryContext()
    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: 5, deloadThreshold: 3, deloadPercentage: 0.10
    )
    context.insert(config)

    let calendar = Calendar.current
    for dayOffset in 0..<3 {
        let date = calendar.date(byAdding: .day, value: dayOffset, to: Date())!
        let session = WorkoutSession(date: date, workoutType: .a)
        context.insert(session)
        let log = ExerciseLog(session: session, exercise: squat, targetWeight: 200, targetReps: 5)
        context.insert(log)
        for n in 1...5 { context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: n == 5 ? 3 : 5)) }
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
    // 3 fails at 200 -> triggers a deload to 180. A 4th fail is then logged
    // AT the deloaded weight (180), simulating a real next session that used
    // ProgressionCalculator's own deloaded output as its target.
    let weights = [200.0, 200.0, 200.0, 180.0]
    for (dayOffset, weight) in weights.enumerated() {
        let date = calendar.date(byAdding: .day, value: dayOffset, to: Date())!
        let session = WorkoutSession(date: date, workoutType: .a)
        context.insert(session)
        let log = ExerciseLog(session: session, exercise: squat, targetWeight: weight, targetReps: 5)
        context.insert(log)
        for n in 1...5 { context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: n == 5 ? 3 : 5)) }
    }
    try context.save()

    // Streak should count only the single fail at the new (180) weight, not
    // all 4 fails across the deload boundary.
    let streak = try ProgressionCalculator.currentFailStreak(for: squat, in: context)
    #expect(streak == 1)

    let config = UserExerciseConfig(
        exercise: squat, startingWeight: 45, weightIncrement: 5,
        setCount: 5, repsPerSet: 5, deloadThreshold: 3, deloadPercentage: 0.10
    )
    context.insert(config)
    try context.save()

    // Below threshold again post-deload -> repeat at 180, not deload a second time to 162.
    let next = try ProgressionCalculator.nextTargetWeight(for: squat, config: config, in: context)
    #expect(next == 180)
}
