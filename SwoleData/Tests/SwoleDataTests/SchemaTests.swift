import Foundation
import Testing
@testable import SwoleData

@Test func fullSchemaBuildsAnInMemoryContainer() throws {
    _ = try makeInMemoryContext()
}

@Test func workoutSessionRestFieldsDefaultToNilAndRoundTrip() throws {
    let context = try makeInMemoryContext()
    let session = WorkoutSession(startedAt: .now, workoutType: .a)
    context.insert(session)
    try context.save()

    #expect(session.restStartDate == nil)
    #expect(session.restEndDate == nil)
    #expect(session.restLabel == nil)

    let start = Date.now
    let end = start.addingTimeInterval(90)
    session.restStartDate = start
    session.restEndDate = end
    session.restLabel = "Rest · next exercise"
    try context.save()

    #expect(session.restStartDate == start)
    #expect(session.restEndDate == end)
    #expect(session.restLabel == "Rest · next exercise")
}
