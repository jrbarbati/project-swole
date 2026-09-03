import Testing
@testable import SwoleData

@Test func totalVolumeTierAtIndexReturnsFixedPrefixInLb() {
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 0, unit: .lb) == 2000)
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 4, unit: .lb) == 20000)
}

@Test func totalVolumeTierAtIndexStepsByTenThousandPastThePrefixInLb() {
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 5, unit: .lb) == 30000)
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 6, unit: .lb) == 40000)
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 15, unit: .lb) == 130000)
}

@Test func totalVolumeTierAtIndexUsesTheRoundKgLadder() {
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 0, unit: .kg) == 1000)
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 4, unit: .kg) == 10000)
    #expect(BadgeCalculator.totalVolumeTier(atIndex: 5, unit: .kg) == 15000)
}

@Test func totalVolumeIndicesReachingReturnsEarnedTiersPlusExactlyOneNext() {
    let result = BadgeCalculator.totalVolumeIndices(reaching: 12000, unit: .lb)
    #expect(result.earned == [0, 1, 2])
    #expect(result.next == 3)
}

@Test func totalVolumeIndicesReachingHandlesValuesFarPastTheFixedPrefix() {
    let result = BadgeCalculator.totalVolumeIndices(reaching: 45000, unit: .lb)
    #expect(result.earned == [0, 1, 2, 3, 4, 5, 6])
    #expect(result.next == 7)
}

@Test func totalVolumeIndicesReachingZeroEarnsNothing() {
    let result = BadgeCalculator.totalVolumeIndices(reaching: 0, unit: .lb)
    #expect(result.earned.isEmpty)
    #expect(result.next == 0)
}
