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

    public init(
        exercise: Exercise?,
        startingWeight: Double,
        weightIncrement: Double,
        setCount: Int,
        repsPerSet: Int,
        deloadThreshold: Int,
        deloadPercentage: Double
    ) {
        self.exercise = exercise
        self.startingWeight = startingWeight
        self.weightIncrement = weightIncrement
        self.setCount = setCount
        self.repsPerSet = repsPerSet
        self.deloadThreshold = deloadThreshold
        self.deloadPercentage = deloadPercentage
    }
}
