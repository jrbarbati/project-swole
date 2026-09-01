import ActivityKit
import Foundation

/// Shared between the app target and the `5x5iveWidget` extension target
/// (added to both targets' Sources build phases — see the widget
/// extension task's setup script). Deliberately NOT part of the SwoleData
/// package: ActivityKit doesn't exist on macOS, and SwoleData's
/// Package.swift declares macOS(.v14) support for local `swift test`.
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var currentExerciseName: String
        public var completedSets: Int
        public var totalSets: Int
        public var nextExerciseName: String?
        public var restStartDate: Date?
        public var restEndDate: Date?

        public init(
            currentExerciseName: String,
            completedSets: Int,
            totalSets: Int,
            nextExerciseName: String?,
            restStartDate: Date?,
            restEndDate: Date?
        ) {
            self.currentExerciseName = currentExerciseName
            self.completedSets = completedSets
            self.totalSets = totalSets
            self.nextExerciseName = nextExerciseName
            self.restStartDate = restStartDate
            self.restEndDate = restEndDate
        }
    }

    public var workoutTypeRawValue: String

    public init(workoutTypeRawValue: String) {
        self.workoutTypeRawValue = workoutTypeRawValue
    }
}
