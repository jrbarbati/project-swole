import Foundation
import SwiftData

@Model
public final class WorkoutTemplateExercise {
    public var workoutType: WorkoutType
    public var exercise: Exercise?
    public var order: Int

    public init(workoutType: WorkoutType, exercise: Exercise?, order: Int) {
        self.workoutType = workoutType
        self.exercise = exercise
        self.order = order
    }
}
