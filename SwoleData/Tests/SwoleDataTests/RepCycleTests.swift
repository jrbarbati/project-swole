import Testing
@testable import SwoleData

@Test func cyclesFromNotStartedThroughTargetDownToZeroThenBackToNotStarted() {
    let target = 5
    var current: Int? = nil
    let expectedSequence: [Int?] = [5, 4, 3, 2, 1, 0, nil, 5]

    for expected in expectedSequence {
        current = RepCycle.next(current: current, target: target)
        #expect(current == expected)
    }
}

@Test func firstTapAlwaysLandsOnTargetRegardlessOfTargetValue() {
    #expect(RepCycle.next(current: nil, target: 5) == 5)
    #expect(RepCycle.next(current: nil, target: 1) == 1)
}
