import Foundation

/// Marker for events sent through `EventBus`. Features may declare their own event types.
public protocol AppEvent: Sendable {}

/// Typed publish/subscribe between Core and features.
///
///     for await change in context.events.stream(of: ClipboardChanged.self) { … }
///
/// Each subscriber gets its own stream; cancelling the consuming task unsubscribes.
@MainActor
public final class EventBus {
    private var subscribers: [ObjectIdentifier: [UUID: (any AppEvent) -> Void]] = [:]

    public init() {}

    public func publish<E: AppEvent>(_ event: E) {
        subscribers[ObjectIdentifier(E.self)]?.values.forEach { $0(event) }
    }

    public func stream<E: AppEvent>(of type: E.Type) -> AsyncStream<E> {
        let (stream, continuation) = AsyncStream.makeStream(of: E.self)
        let key = ObjectIdentifier(type)
        let token = UUID()
        subscribers[key, default: [:]][token] = { event in
            if let event = event as? E { continuation.yield(event) }
        }
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[key]?[token] = nil }
        }
        return stream
    }

    var subscriberCount: Int { subscribers.values.reduce(0) { $0 + $1.count } }
}
