import Testing
@testable import _x5ive

@MainActor
struct WorkoutIntentBusTests {
    @Test func sendDeliversImmediatelyToAnAlreadySubscribedHandler() {
        let bus = WorkoutIntentBus.shared
        var received: [WorkoutIntentBus.Action] = []
        bus.subscribe { received.append($0) }
        defer { bus.unsubscribe() }

        bus.send(.skipRest)

        #expect(received == [.skipRest])
    }

    @Test func sendBeforeAnySubscriberBuffersOneActionForTheNextSubscribe() {
        let bus = WorkoutIntentBus.shared
        bus.unsubscribe()

        bus.send(.skipRest)

        var received: [WorkoutIntentBus.Action] = []
        bus.subscribe { received.append($0) }
        defer { bus.unsubscribe() }

        #expect(received == [.skipRest])
    }

    @Test func unsubscribeStopsFurtherDelivery() {
        let bus = WorkoutIntentBus.shared
        var received: [WorkoutIntentBus.Action] = []
        bus.subscribe { received.append($0) }
        bus.unsubscribe()

        bus.send(.logNextSetAtTarget)

        #expect(received.isEmpty)
    }
}

extension WorkoutIntentBus.Action: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.skipRest, .skipRest), (.logNextSetAtTarget, .logNextSetAtTarget): true
        default: false
        }
    }
}
