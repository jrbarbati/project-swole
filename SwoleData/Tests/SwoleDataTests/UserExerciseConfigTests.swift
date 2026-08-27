import Testing
import SwiftData
@testable import SwoleData

@Test func userExerciseConfigLinksToItsExercise() throws {
    let container = try ModelContainer(
        for: Exercise.self, UserExerciseConfig.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = ModelContext(container)

    let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
    context.insert(squat)
    context.insert(UserExerciseConfig(
        exercise: squat,
        startingWeight: 45,
        weightIncrement: 5,
        setCount: 5,
        repsPerSet: 5,
        deloadThreshold: 3,
        deloadPercentage: 0.10
    ))
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<UserExerciseConfig>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.exercise?.name == "Squat")
    #expect(fetched.first?.startingWeight == 45)
    #expect(fetched.first?.weightIncrement == 5)
    #expect(fetched.first?.deloadThreshold == 3)
    #expect(fetched.first?.deloadPercentage == 0.10)
    #expect(fetched.first?.weightOverride == nil)
}
