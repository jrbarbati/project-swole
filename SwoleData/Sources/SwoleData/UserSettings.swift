import Foundation
import SwiftData

@Model
public final class UserSettings {
    public var unit: MeasurementUnit
    public var lastCompletedWorkoutType: WorkoutType?

    public init(unit: MeasurementUnit, lastCompletedWorkoutType: WorkoutType?) {
        self.unit = unit
        self.lastCompletedWorkoutType = lastCompletedWorkoutType
    }
}
