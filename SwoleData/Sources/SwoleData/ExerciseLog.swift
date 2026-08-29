import Foundation
import SwiftData

@Model
public final class ExerciseLog {
    public var session: WorkoutSession?
    public var exercise: Exercise?
    public var targetWeight: Double
    public var targetReps: Int
    public var order: Int = 0
    public var note: String?
    /// IDs of `WarmupSet`s checked off in the exercise sheet, so warmup
    /// progress survives an app relaunch mid-workout.
    public var completedWarmupIDs: [Int] = []
    @Relationship(deleteRule: .cascade, inverse: \SetLog.exerciseLog)
    public var sets: [SetLog] = []

    public init(session: WorkoutSession?, exercise: Exercise?, targetWeight: Double, targetReps: Int, order: Int = 0, note: String? = nil) {
        self.session = session
        self.exercise = exercise
        self.targetWeight = targetWeight
        self.targetReps = targetReps
        self.order = order
        self.note = note
    }

    public var succeeded: Bool {
        !sets.isEmpty && sets.allSatisfy { ($0.repsCompleted ?? Int.min) >= targetReps }
    }
}
