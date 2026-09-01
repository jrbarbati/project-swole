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

        /// "A" or "B" — the workout badge. Raw value of `WorkoutType`.
        public var workoutTypeLabel: String
        /// Preformatted, unit-resolved target weight, e.g. "185 lb".
        /// Formatted app-side so the extension never needs UserSettings.
        public var targetWeightLabel: String
        /// Per-set results for the current exercise, in set order.
        /// `nil` = unlogged. Count must equal `totalSets`.
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

        // MARK: Derived

        /// A rest window, or nil when the lifter is under the bar.
        public var restWindow: ClosedRange<Date>? {
            guard let restStartDate, let restEndDate, restEndDate > restStartDate else { return nil }
            return restStartDate...restEndDate
        }

        public var isResting: Bool { restWindow != nil }

        /// 1-based number of the set the lifter is about to do. Clamped so a
        /// finished exercise reads as its last set rather than one past it.
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

        /// First word of the exercise name — the only thing that fits in the
        /// Dynamic Island's compact leading region.
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

/// Mirrors `SetTile`'s private TileState so both the app and the widget can
/// describe a set the same way. Carries the rep count so the widget doesn't
/// have to re-derive the label.
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
