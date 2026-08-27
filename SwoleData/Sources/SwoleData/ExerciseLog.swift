import Foundation
import SwiftData

@Model
public final class ExerciseLog {
    public var session: WorkoutSession?
    public var exercise: Exercise?
    public var targetWeight: Double
    public var targetReps: Int
    public var order: Int = 0
    /// Per-exercise note, captured in the exercise sheet.
    public var note: String?
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
