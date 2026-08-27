import Testing
@testable import SwoleData

@Test func workoutTypeHasExactlyAAndB() {
    #expect(WorkoutType.allCases == [.a, .b])
    #expect(WorkoutType.a.rawValue == "A")
    #expect(WorkoutType.b.rawValue == "B")
}

@Test func measurementUnitHasExactlyLbAndKg() {
    #expect(MeasurementUnit.allCases == [.lb, .kg])
}
