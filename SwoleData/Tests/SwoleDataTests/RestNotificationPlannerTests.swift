import Testing
import Foundation
@testable import SwoleData

@Test func secondsUntilFireReturnsPositiveIntervalForAFutureEndDate() {
    let now = Date(timeIntervalSince1970: 1_000)
    let end = now.addingTimeInterval(90)

    let seconds = RestNotificationPlanner.secondsUntilFire(restEndDate: end, now: now)

    #expect(seconds == 90)
}

@Test func secondsUntilFireReturnsNilForAnAlreadyElapsedEndDate() {
    let now = Date(timeIntervalSince1970: 1_000)
    let end = now.addingTimeInterval(-1)

    #expect(RestNotificationPlanner.secondsUntilFire(restEndDate: end, now: now) == nil)
}

@Test func secondsUntilFireReturnsNilWhenEndDateEqualsNow() {
    let now = Date(timeIntervalSince1970: 1_000)

    #expect(RestNotificationPlanner.secondsUntilFire(restEndDate: now, now: now) == nil)
}
