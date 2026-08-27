import Foundation
import SwiftData

public enum StandardSeed {
    @discardableResult
    public static func seed(in context: ModelContext) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        guard existing.isEmpty else {
            return false
        }

        let squat = Exercise(name: "Squat", defaultSetCount: 5, defaultRepsPerSet: 5)
        let bench = Exercise(name: "Bench Press", defaultSetCount: 5, defaultRepsPerSet: 5)
        let row = Exercise(name: "Barbell Row", defaultSetCount: 5, defaultRepsPerSet: 5)
        let ohp = Exercise(name: "Overhead Press", defaultSetCount: 5, defaultRepsPerSet: 5)
        let deadlift = Exercise(name: "Deadlift", defaultSetCount: 1, defaultRepsPerSet: 5)
        
        for exercise in [squat, bench, row, ohp, deadlift] {
            context.insert(exercise)
        }

        func makeConfig(_ exercise: Exercise, starting: Double, increment: Double) {
            context.insert(UserExerciseConfig(
                exercise: exercise,
                startingWeight: starting,
                weightIncrement: increment,
                setCount: exercise.defaultSetCount,
                repsPerSet: exercise.defaultRepsPerSet,
                deloadThreshold: 3,
                deloadPercentage: 0.10,
                restSecondsOnSuccess: 90,
                restSecondsOnFail: 180
            ))
        }
        
        makeConfig(squat, starting: 45, increment: 5)
        makeConfig(bench, starting: 45, increment: 5)
        makeConfig(row, starting: 45, increment: 5)
        makeConfig(ohp, starting: 45, increment: 5)
        makeConfig(deadlift, starting: 95, increment: 10)

        let templateEntries: [(WorkoutType, Exercise, Int)] = [
            (.a, squat, 0), (.a, bench, 1), (.a, row, 2),
            (.b, squat, 0), (.b, ohp, 1), (.b, deadlift, 2),
        ]
        
        for (type, exercise, order) in templateEntries {
            context.insert(WorkoutTemplateExercise(workoutType: type, exercise: exercise, order: order))
        }

        context.insert(UserSettings(unit: .lb, lastCompletedWorkoutType: nil))

        try context.save()
        return true
    }
}
