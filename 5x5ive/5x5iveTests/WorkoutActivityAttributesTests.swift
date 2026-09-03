import Foundation
import Testing
@testable import _x5ive

struct WorkoutActivityAttributesTests {
    @Test func contentStateEqualityReflectsAllFields() {
        let base = WorkoutActivityAttributes.ContentState(
            currentExerciseName: "Squat",
            completedSets: 2,
            totalSets: 5,
            nextExerciseName: "Bench Press",
            restStartDate: nil,
            restEndDate: nil
        )
        let same = base
        var different = base
        different.completedSets = 3

        #expect(base == same)
        #expect(base != different)
    }

    @Test func attributesCarryTheWorkoutType() {
        let attributes = WorkoutActivityAttributes(workoutTypeRawValue: "A")
        #expect(attributes.workoutTypeRawValue == "A")
    }

    @Test func newFieldsDefaultForBackwardCompatibleCallSites() {
        let state = WorkoutActivityAttributes.ContentState(
            currentExerciseName: "Squat",
            completedSets: 0,
            totalSets: 5,
            nextExerciseName: nil,
            restStartDate: nil,
            restEndDate: nil
        )

        #expect(state.workoutTypeLabel == "")
        #expect(state.targetWeightLabel == "")
        #expect(state.setReps == [])
        #expect(state.targetReps == 5)
        #expect(state.restDuration == nil)
    }

    @Test func restWindowIsNilWithoutBothDates() {
        var state = WorkoutActivityAttributes.ContentState.resting
        state.restEndDate = nil
        #expect(state.restWindow == nil)
        #expect(!state.isResting)
    }

    @Test func restWindowIsNilWhenEndDoesNotFollowStart() {
        var state = WorkoutActivityAttributes.ContentState.resting
        state.restEndDate = state.restStartDate
        #expect(state.restWindow == nil)
    }

    @Test func restWindowIsPresentWhenEndFollowsStart() {
        let state = WorkoutActivityAttributes.ContentState.resting
        #expect(state.restWindow != nil)
        #expect(state.isResting)
    }

    @Test func currentSetNumberIsCompletedSetsPlusOne() {
        var state = WorkoutActivityAttributes.ContentState.resting
        state.completedSets = 2
        state.totalSets = 5
        #expect(state.currentSetNumber == 3)
    }

    @Test func currentSetNumberClampsToTheLastSetWhenExerciseIsFinished() {
        var state = WorkoutActivityAttributes.ContentState.resting
        state.completedSets = 5
        state.totalSets = 5
        #expect(state.currentSetNumber == 5)
    }

    @Test func currentSetNumberFloorsAtOneWithNoSets() {
        var state = WorkoutActivityAttributes.ContentState.resting
        state.completedSets = 0
        state.totalSets = 0
        #expect(state.currentSetNumber == 1)
    }

    @Test func tilesMarkHitsMissesNextAndEmpty() {
        var state = WorkoutActivityAttributes.ContentState.resting
        state.totalSets = 4
        state.targetReps = 5
        state.setReps = [5, 3, nil, nil]

        #expect(state.tiles == [.hit(5), .miss(3), .next, .empty])
    }

    /// A fully empty `setReps` has no `nil` to point `.next` at, so every
    /// padded slot reads as `.empty`.
    @Test func tilesPadShortSetRepsArraysToTotalSets() {
        var state = WorkoutActivityAttributes.ContentState.resting
        state.totalSets = 3
        state.setReps = []

        #expect(state.tiles == [.empty, .empty, .empty])
    }

    @Test func tilesHaveNoNextWhenEveryLoggedSetIsFilled() {
        var state = WorkoutActivityAttributes.ContentState.resting
        state.totalSets = 2
        state.targetReps = 5
        state.setReps = [5, 3]

        #expect(state.tiles == [.hit(5), .miss(3)])
    }

    @Test func shortExerciseNameIsTheFirstWord() {
        var state = WorkoutActivityAttributes.ContentState.resting
        state.currentExerciseName = "Barbell Row"
        #expect(state.shortExerciseName == "Barbell")
    }

    @Test func shortExerciseNameFallsBackToTheWholeNameWhenThereIsNoSpace() {
        var state = WorkoutActivityAttributes.ContentState.resting
        state.currentExerciseName = "Squat"
        #expect(state.shortExerciseName == "Squat")
    }

    @Test func setsLabelIsCompletedOverTotal() {
        var state = WorkoutActivityAttributes.ContentState.resting
        state.completedSets = 3
        state.totalSets = 5
        #expect(state.setsLabel == "3/5")
    }

    @Test func setTileStateLabelsUseAnEnDashForNextAndEmpty() {
        #expect(SetTileState.hit(5).label == "5")
        #expect(SetTileState.miss(3).label == "3")
        #expect(SetTileState.next.label == "\u{2013}")
        #expect(SetTileState.empty.label == "\u{2013}")
    }
}

private extension WorkoutActivityAttributes.ContentState {
    /// Mirrors the widget's own preview fixture.
    static var resting: Self {
        .init(
            currentExerciseName: "Bench Press",
            completedSets: 3,
            totalSets: 5,
            nextExerciseName: "Barbell Row",
            restStartDate: .now.addingTimeInterval(-62),
            restEndDate: .now.addingTimeInterval(88),
            workoutTypeLabel: "A",
            targetWeightLabel: "185 lb",
            setReps: [5, 5, 3, nil, nil],
            targetReps: 5,
            restDuration: 150
        )
    }
}
