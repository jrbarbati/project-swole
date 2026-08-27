import Foundation
import SwiftData

@Model
public final class WorkoutSession {
    @Attribute(originalName: "date")
    public var startedAt: Date
    public var workoutType: WorkoutType
    public var finishedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.session)
    public var exerciseLogs: [ExerciseLog] = []

    public init(startedAt: Date, workoutType: WorkoutType, finishedAt: Date? = nil) {
        self.startedAt = startedAt
        self.workoutType = workoutType
        self.finishedAt = finishedAt
    }
}
