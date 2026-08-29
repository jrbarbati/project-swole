import Testing
@testable import SwoleData

@Test func knownCombinationProducesExpectedKilocalories() {
    // 5.0 MET * 80kg * 1 hour = 400 kcal
    let kcal = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 80, duration: 3600)
    #expect(abs(kcal - 400) < 0.001)
}

@Test func zeroDurationProducesZeroKilocalories() {
    let kcal = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 80, duration: 0)
    #expect(kcal == 0)
}

@Test func scalesLinearlyWithBodyWeight() {
    let base = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 80, duration: 3600)
    let doubled = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 160, duration: 3600)
    #expect(abs(doubled - base * 2) < 0.001)
}

@Test func scalesLinearlyWithDuration() {
    let base = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 80, duration: 3600)
    let doubled = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 80, duration: 7200)
    #expect(abs(doubled - base * 2) < 0.001)
}

@Test func customMETOverridesDefault() {
    let kcal = WorkoutEnergyEstimate.kilocalories(bodyWeightKg: 80, duration: 3600, met: 1.0)
    #expect(abs(kcal - 80) < 0.001)
}
