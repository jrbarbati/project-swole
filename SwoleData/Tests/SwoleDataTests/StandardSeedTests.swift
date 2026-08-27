import Testing
import SwiftData
@testable import SwoleData

@Test func seedCreatesStandardFiveByFiveSetup() throws {
    let context = try makeInMemoryContext()

    let didSeed = try StandardSeed.seed(in: context)
    #expect(didSeed == true)

    let exercises = try context.fetch(FetchDescriptor<Exercise>())
    #expect(exercises.count == 5)
    #expect(Set(exercises.map(\.name)) == ["Squat", "Bench Press", "Overhead Press", "Deadlift", "Barbell Row"])

    let configs = try context.fetch(FetchDescriptor<UserExerciseConfig>())
    #expect(configs.count == 5)
    let deadliftConfig = configs.first { $0.exercise?.name == "Deadlift" }
    #expect(deadliftConfig?.weightIncrement == 10)
    #expect(deadliftConfig?.setCount == 1)
    let squatConfig = configs.first { $0.exercise?.name == "Squat" }
    #expect(squatConfig?.weightIncrement == 5)
    #expect(squatConfig?.setCount == 5)

    let templateEntries = try context.fetch(FetchDescriptor<WorkoutTemplateExercise>())
    #expect(templateEntries.count == 6)
    let dayA = templateEntries.filter { $0.workoutType == .a }
    #expect(Set(dayA.compactMap { $0.exercise?.name }) == ["Squat", "Bench Press", "Barbell Row"])
    let dayB = templateEntries.filter { $0.workoutType == .b }
    #expect(Set(dayB.compactMap { $0.exercise?.name }) == ["Squat", "Overhead Press", "Deadlift"])

    let settings = try context.fetch(FetchDescriptor<UserSettings>())
    #expect(settings.count == 1)
    #expect(settings.first?.unit == .lb)
    #expect(settings.first?.lastCompletedWorkoutType == nil)
}

@Test func seedDoesNotDuplicateOnSecondCall() throws {
    let context = try makeInMemoryContext()

    _ = try StandardSeed.seed(in: context)
    let didSeedAgain = try StandardSeed.seed(in: context)

    #expect(didSeedAgain == false)
    #expect(try context.fetch(FetchDescriptor<Exercise>()).count == 5)
}

@Test func seedSetsDefaultRestDurationsOnEveryConfig() throws {
    let context = try makeInMemoryContext()
    _ = try StandardSeed.seed(in: context)

    let configs = try context.fetch(FetchDescriptor<UserExerciseConfig>())
    #expect(configs.allSatisfy { $0.restSecondsOnSuccess == 90 })
    #expect(configs.allSatisfy { $0.restSecondsOnFail == 180 })
}
