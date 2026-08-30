import Foundation
import SwiftData

public enum StandardSeed {
    @discardableResult
    public static func seed(in context: ModelContext) throws -> Bool {
        guard try context.fetch(FetchDescriptor<Exercise>()).isEmpty else {
            return false
        }

        let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
        let bench = Exercise(name: "Bench Press", defaultSetCount: 5, defaultRepsPerSet: 5)
        let row = Exercise(name: "Barbell Row", defaultSetCount: 5, defaultRepsPerSet: 5)
        let overheadPress = Exercise(name: "Overhead Press", defaultSetCount: 5, defaultRepsPerSet: 5)
        let deadlift = Exercise(name: "Deadlift", defaultSetCount: 1, defaultRepsPerSet: 5)

        for exercise in [squat, bench, row, overheadPress, deadlift] {
            context.insert(exercise)
        }

        func insertConfig(for exercise: Exercise, startingWeight: Double, increment: Double) {
            context.insert(UserExerciseConfig(
                exercise: exercise,
                startingWeight: startingWeight,
                weightIncrement: increment,
                setCount: exercise.defaultSetCount,
                repsPerSet: exercise.defaultRepsPerSet,
                deloadThreshold: 3,
                deloadPercentage: 0.10,
                restSecondsOnSuccess: 90,
                restSecondsOnFail: 180
            ))
        }

        insertConfig(for: squat, startingWeight: 45, increment: 5)
        insertConfig(for: bench, startingWeight: 45, increment: 5)
        insertConfig(for: row, startingWeight: 45, increment: 5)
        insertConfig(for: overheadPress, startingWeight: 45, increment: 5)
        insertConfig(for: deadlift, startingWeight: 95, increment: 10)

        let templateEntries: [(workoutType: WorkoutType, exercise: Exercise, order: Int)] = [
            (.a, squat, 0), (.a, bench, 1), (.a, row, 2),
            (.b, squat, 0), (.b, overheadPress, 1), (.b, deadlift, 2),
        ]

        for entry in templateEntries {
            context.insert(WorkoutTemplateExercise(
                workoutType: entry.workoutType,
                exercise: entry.exercise,
                order: entry.order
            ))
        }

        context.insert(UserSettings(unit: .lb, lastCompletedWorkoutType: nil))
        context.insert(GamificationState(totalXP: 0))

        try context.save()
        return true
    }
}
