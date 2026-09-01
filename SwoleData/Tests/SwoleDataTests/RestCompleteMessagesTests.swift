import Testing
@testable import SwoleData

@Test func allContainsTheNineApprovedMessagesAndExcludesTheDroppedOne() {
    #expect(RestCompleteMessages.all.count == 9)
    #expect(Set(RestCompleteMessages.all).count == 9)
    #expect(!RestCompleteMessages.all.contains("Clock ran out. You didn't."))
}

@Test func randomAlwaysReturnsAMemberOfAll() {
    for _ in 0..<50 {
        #expect(RestCompleteMessages.all.contains(RestCompleteMessages.random()))
    }
}
