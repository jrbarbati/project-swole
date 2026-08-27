import Testing
@testable import SwoleData

@Test func nextWorkoutTypeDefaultsToAWithNoHistory() {
    let settings = UserSettings(unit: .lb, lastCompletedWorkoutType: nil)
    #expect(WorkoutScheduler.nextWorkoutType(after: settings) == .a)
}

@Test func nextWorkoutTypeAlternatesFromA() {
    let settings = UserSettings(unit: .lb, lastCompletedWorkoutType: .a)
    #expect(WorkoutScheduler.nextWorkoutType(after: settings) == .b)
}

@Test func nextWorkoutTypeAlternatesFromB() {
    let settings = UserSettings(unit: .lb, lastCompletedWorkoutType: .b)
    #expect(WorkoutScheduler.nextWorkoutType(after: settings) == .a)
}
