import ActivityKit
import Foundation

/// Shared with the `5x5iveWidget` extension target. Not in SwoleData:
/// ActivityKit is unavailable on macOS, which SwoleData's package must
/// still support for local `swift test`.
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var currentExerciseName: String
        public var completedSets: Int
        public var totalSets: Int
        public var nextExerciseName: String?
        public var restStartDate: Date?
        public var restEndDate: Date?

        /// "A" or "B" — raw value of `WorkoutType`.
        public var workoutTypeLabel: String
        /// e.g. "185 lb" — formatted app-side so the extension never needs UserSettings.
        public var targetWeightLabel: String
        /// Per-set results in set order; `nil` = unlogged. Count must equal `totalSets`.
        public var setReps: [Int?]
        /// Hit/miss threshold for a tile, and the rep hint when not resting.
        public var targetReps: Int
        /// Full length of the running rest, for the "REST · 2:30" label.
        public var restDuration: TimeInterval?

        public init(
            currentExerciseName: String,
            completedSets: Int,
            totalSets: Int,
            nextExerciseName: String?,
            restStartDate: Date?,
            restEndDate: Date?,
            workoutTypeLabel: String = "",
            targetWeightLabel: String = "",
            setReps: [Int?] = [],
            targetReps: Int = 5,
            restDuration: TimeInterval? = nil
        ) {
            self.currentExerciseName = currentExerciseName
            self.completedSets = completedSets
            self.totalSets = totalSets
            self.nextExerciseName = nextExerciseName
            self.restStartDate = restStartDate
            self.restEndDate = restEndDate
            self.workoutTypeLabel = workoutTypeLabel
            self.targetWeightLabel = targetWeightLabel
            self.setReps = setReps
            self.targetReps = targetReps
            self.restDuration = restDuration
        }

        /// nil when the lifter is under the bar.
        public var restWindow: ClosedRange<Date>? {
            guard let restStartDate, let restEndDate, restEndDate > restStartDate else { return nil }
            return restStartDate...restEndDate
        }

        public var isResting: Bool { restWindow != nil }

        /// 1-based; clamped to `totalSets` once the exercise is finished.
        public var currentSetNumber: Int {
            min(completedSets + 1, max(totalSets, 1))
        }

        /// Tile states, padded to `totalSets` if `setReps` arrives short.
        public var tiles: [SetTileState] {
            let nextIndex = setReps.firstIndex(where: { $0 == nil })
            return (0..<max(totalSets, setReps.count)).map { index in
                let reps = index < setReps.count ? setReps[index] : nil
                guard let reps else { return index == nextIndex ? .next : .empty }
                return reps >= targetReps ? .hit(reps) : .miss(reps)
            }
        }

        /// Fits the Dynamic Island's compact leading region.
        public var shortExerciseName: String {
            currentExerciseName.split(separator: " ").first.map(String.init) ?? currentExerciseName
        }

        public var setsLabel: String { "\(completedSets)/\(totalSets)" }
    }

    public var workoutTypeRawValue: String

    public init(workoutTypeRawValue: String) {
        self.workoutTypeRawValue = workoutTypeRawValue
    }
}

/// Mirrors `SetTile`'s private TileState so app and widget agree on a set's
/// display state; carries reps so the widget doesn't re-derive the label.
public enum SetTileState: Codable, Hashable {
    case hit(Int)
    case miss(Int)
    case next
    case empty

    public var label: String {
        switch self {
        case .hit(let reps), .miss(let reps): "\(reps)"
        case .next, .empty: "\u{2013}"
        }
    }
}
