import Testing
import SwiftData
@testable import SwoleData

@Test func gamificationStateStoresTotalXPAndDefaultsToZero() throws {
    let context = try makeInMemoryContext()

    let state = GamificationState()
    context.insert(state)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<GamificationState>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.totalXP == 0)

    fetched.first?.totalXP = 250
    try context.save()

    let refetched = try context.fetch(FetchDescriptor<GamificationState>())
    #expect(refetched.first?.totalXP == 250)
}
