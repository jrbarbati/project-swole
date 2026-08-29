import Testing
@testable import SwoleData

@Test func xpConstantsMatchDesignedRates() {
    #expect(XPCalculator.workoutXP == 60)
    #expect(XPCalculator.prBonusXP == 20)
    #expect(XPCalculator.weeklyBonusXP == 120)
}

@Test func xpForLevelFollowsThePowerCurveBelowTheCap() {
    #expect(XPCalculator.xpForLevel(1) == 50)
    #expect(XPCalculator.xpForLevel(2) == 141)
    #expect(XPCalculator.xpForLevel(13) == 2344)
}

@Test func xpForLevelIsCappedAtTwentyFiveHundredPastLevelThirteen() {
    #expect(XPCalculator.xpForLevel(14) == 2500)
    #expect(XPCalculator.xpForLevel(20) == 2500)
    #expect(XPCalculator.xpForLevel(50) == 2500)
}

@Test func levelForXPStartsAtOneAndIncrementsAtEachThreshold() {
    #expect(XPCalculator.level(forXP: 0) == 1)
    #expect(XPCalculator.level(forXP: 49) == 1)
    #expect(XPCalculator.level(forXP: 50) == 2)
    #expect(XPCalculator.level(forXP: 190) == 2)
    #expect(XPCalculator.level(forXP: 191) == 3)
}

@Test func progressReportsXPEarnedWithinTheCurrentLevel() {
    let progress = XPCalculator.progress(forXP: 60)
    #expect(progress.level == 2)
    #expect(progress.current == 10)
    #expect(progress.needed == 141)
}

@Test func progressAtExactlyZeroXP() {
    let progress = XPCalculator.progress(forXP: 0)
    #expect(progress.level == 1)
    #expect(progress.current == 0)
    #expect(progress.needed == 50)
}
