import Testing
import SwiftData
import Foundation
@testable import SwoleData

@Test func succeededIsTrueOnlyWhenEverySetHitTargetReps() throws {
    let container = try ModelContainer(
        for: Exercise.self, WorkoutSession.self, ExerciseLog.self, SetLog.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    let session = WorkoutSession(startedAt: Date(), workoutType: .a)
    context.insert(squat)
    context.insert(session)

    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 135, targetReps: 5)
    context.insert(log)
    for n in 1...5 {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: n == 5 ? 3 : 5))
    }
    try context.save()

    #expect(log.succeeded == false)

    log.sets.first { $0.setNumber == 5 }?.repsCompleted = 5
    try context.save()
    #expect(log.succeeded == true)
}

@Test func succeededIsFalseWhenAnySetIsNotStarted() throws {
    let container = try ModelContainer(
        for: Exercise.self, WorkoutSession.self, ExerciseLog.self, SetLog.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    let session = WorkoutSession(startedAt: Date(), workoutType: .a)
    context.insert(squat)
    context.insert(session)

    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 135, targetReps: 5)
    context.insert(log)
    for n in 1...4 {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: 5))
    }
    context.insert(SetLog(exerciseLog: log, setNumber: 5, repsCompleted: nil))
    try context.save()

    #expect(log.succeeded == false)
}

@Test func deletingSessionCascadesToLogsAndSets() throws {
    let container = try ModelContainer(
        for: Exercise.self, WorkoutSession.self, ExerciseLog.self, SetLog.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    let session = WorkoutSession(startedAt: Date(), workoutType: .a)
    context.insert(squat)
    context.insert(session)
    let log = ExerciseLog(session: session, exercise: squat, targetWeight: 135, targetReps: 5)
    context.insert(log)
    for n in 1...5 {
        context.insert(SetLog(exerciseLog: log, setNumber: n, repsCompleted: 5))
    }
    try context.save()

    context.delete(session)
    try context.save()

    #expect(try context.fetch(FetchDescriptor<ExerciseLog>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<Exercise>()).count == 1)
}
