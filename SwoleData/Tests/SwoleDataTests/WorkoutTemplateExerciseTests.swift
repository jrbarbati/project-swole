import Testing
import SwiftData
@testable import SwoleData

@Test func sameExerciseCanAppearOnBothWorkoutDays() throws {
    let context = try makeInMemoryContext()

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    context.insert(WorkoutTemplateExercise(workoutType: .a, exercise: squat, order: 0))
    context.insert(WorkoutTemplateExercise(workoutType: .b, exercise: squat, order: 0))
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<WorkoutTemplateExercise>())
    #expect(fetched.count == 2)
    #expect(Set(fetched.map(\.workoutType)) == [.a, .b])
    #expect(fetched.allSatisfy { $0.exercise?.name == "Squat" })
}
