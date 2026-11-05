import Testing
@testable import Core

private struct Ping: AppEvent { let n: Int }
private struct Pong: AppEvent {}

@MainActor
struct EventBusTests {
    @Test func everySubscriberReceivesOnlyItsEventType() async {
        let bus = EventBus()
        var first = bus.stream(of: Ping.self).makeAsyncIterator()
        var second = bus.stream(of: Ping.self).makeAsyncIterator()
        _ = bus.stream(of: Pong.self)

        bus.publish(Ping(n: 1))
        bus.publish(Pong())
        bus.publish(Ping(n: 2))

        #expect(await first.next()?.n == 1)
        #expect(await first.next()?.n == 2)
        #expect(await second.next()?.n == 1)
    }

    @Test func cancelledSubscriberIsRemoved() async {
        let bus = EventBus()
        let task = Task { for await _ in bus.stream(of: Ping.self) {} }
        await Task.yield()
        #expect(bus.subscriberCount == 1)

        task.cancel()
        // onTermination hops back to the main actor; give it a few turns.
        for _ in 0..<20 where bus.subscriberCount > 0 { await Task.yield() }
        #expect(bus.subscriberCount == 0)
    }
}
