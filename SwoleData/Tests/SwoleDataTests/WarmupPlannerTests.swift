import Testing
@testable import SwoleData

@Test func warmupPlanIsEmptyWhenWorkingWeightIsAtOrBelowTheBar() {
    #expect(WarmupPlanner.plan(workingWeight: 45, barWeight: 45, increment: 5).isEmpty)
    #expect(WarmupPlanner.plan(workingWeight: 20, barWeight: 45, increment: 5).isEmpty)
}

@Test func warmupPlanRampsFromEmptyBarThroughRoundedFractionsOfWorkingWeight() {
    let plan = WarmupPlanner.plan(workingWeight: 135, barWeight: 45, increment: 5)

    #expect(plan.map(\.weight) == [45, 90, 110, 125])
    #expect(plan.map(\.reps) == [5, 5, 3, 2])
    #expect(plan.map(\.id) == [0, 1, 2, 3])
}

@Test func warmupPlanRoundsEachStepDownToTheLiftsIncrement() {
    let plan = WarmupPlanner.plan(workingWeight: 227, barWeight: 20, increment: 10)

    #expect(!plan.isEmpty)
    for warmup in plan {
        #expect(warmup.weight.truncatingRemainder(dividingBy: 10) == 0)
    }
}

@Test func warmupPlanDropsDuplicateStepsForLightWorkingWeights() {
    let plan = WarmupPlanner.plan(workingWeight: 50, barWeight: 45, increment: 5)

    #expect(plan.map(\.weight) == [45])
}

@Test func warmupPlanNeverIncludesAStepAtOrAboveTheWorkingWeight() {
    let plan = WarmupPlanner.plan(workingWeight: 135, barWeight: 45, increment: 5)

    #expect(plan.allSatisfy { $0.weight < 135 })
}

@Test func warmupPlanFirstStepIsAlwaysTheEmptyBar() {
    let plan = WarmupPlanner.plan(workingWeight: 315, barWeight: 45, increment: 5)

    #expect(plan.first?.weight == 45)
    #expect(plan.first?.reps == 5)
}
