import Foundation
import SwiftData

@Model
public final class WorkoutSession {
    public var date: Date
    public var workoutType: WorkoutType
    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.session)
    public var exerciseLogs: [ExerciseLog] = []

    public init(date: Date, workoutType: WorkoutType) {
        self.date = date
        self.workoutType = workoutType
    }
}
