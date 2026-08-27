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
