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
}
