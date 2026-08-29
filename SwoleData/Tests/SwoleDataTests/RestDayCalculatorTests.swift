import Testing
import Foundation
@testable import SwoleData

private let calendar = Calendar.current

private func day(_ offset: Int, from reference: Date = .now) -> Date {
    calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: reference))!
}

@Test func dayWithNoSessionsIsNotRest() {
    #expect(RestDayCalculator.isRestDay(day(0), sessionDates: []) == false)
}

@Test func todayIsRestWhenYesterdayWasTrained() {
    // The reported bug: a workout yesterday should mark today REST too,
    // not just past days.
    let sessionDates = [day(-1)]
    #expect(RestDayCalculator.isRestDay(day(0), sessionDates: sessionDates) == true)
}

@Test func dayWithASessionThatDayIsNotRest() {
    let sessionDates = [day(0)]
    #expect(RestDayCalculator.isRestDay(day(0), sessionDates: sessionDates) == false)
}

@Test func restDayStaysRestOnSubsequentUntrainedDaysUntilTrainedAgain() {
    let sessionDates = [day(-3)]
    #expect(RestDayCalculator.isRestDay(day(-2), sessionDates: sessionDates) == true)
    #expect(RestDayCalculator.isRestDay(day(-1), sessionDates: sessionDates) == true)
    #expect(RestDayCalculator.isRestDay(day(0), sessionDates: sessionDates) == true)
}

@Test func dayIsNotRestBeforeAnyTrainingHasEverHappened() {
    // A session two days from now shouldn't retroactively mark today rest —
    // rest only follows training, it doesn't precede it.
    let sessionDates = [day(2)]
    #expect(RestDayCalculator.isRestDay(day(0), sessionDates: sessionDates) == false)
}

@Test func trainingResumesNotRestEvenWithEarlierHistory() {
    let sessionDates = [day(-3), day(0)]
    #expect(RestDayCalculator.isRestDay(day(0), sessionDates: sessionDates) == false)
}
