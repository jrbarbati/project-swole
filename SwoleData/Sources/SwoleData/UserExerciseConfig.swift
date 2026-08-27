import Foundation
import SwiftData

@Model
public final class UserExerciseConfig {
    public var exercise: Exercise?
    public var startingWeight: Double
    public var weightIncrement: Double
    public var setCount: Int
    public var repsPerSet: Int
    public var deloadThreshold: Int
    public var deloadPercentage: Double
    public var restSecondsOnSuccess: Int = 90
    public var restSecondsOnFail: Int = 180
    /// One-shot manual weight nudge for the next session started for this
    /// exercise. Consumed (set back to `nil`) by `WorkoutSessionService`
    /// once a session picks it up.
    public var weightOverride: Double?

    public init(
        exercise: Exercise?,
        startingWeight: Double,
        weightIncrement: Double,
        setCount: Int,
        repsPerSet: Int,
        deloadThreshold: Int,
        deloadPercentage: Double,
        restSecondsOnSuccess: Int = 90,
        restSecondsOnFail: Int = 180
    ) {
        self.exercise = exercise
        self.startingWeight = startingWeight
        self.weightIncrement = weightIncrement
        self.setCount = setCount
        self.repsPerSet = repsPerSet
        self.deloadThreshold = deloadThreshold
        self.deloadPercentage = deloadPercentage
        self.restSecondsOnSuccess = restSecondsOnSuccess
        self.restSecondsOnFail = restSecondsOnFail
        self.weightOverride = nil
    }
}
