import Testing
@testable import Core

@MainActor
struct ActionRegistryTests {
    let registry = ActionRegistry()

    @Test func performsRegisteredActionWithInput() async throws {
        registry.register([
            FeatureAction(id: "a.upper", title: "Upper") { input in
                guard case .text(let s) = input else { return .none }
                return .text(s.uppercased())
            },
        ], for: "a")

        let output = try await registry.perform("a.upper", input: .text("hi"))
        guard case .text(let result) = output else { Issue.record("expected text"); return }
        #expect(result == "HI")
    }

    @Test func unknownActionThrows() async {
        await #expect(throws: ActionError.notFound("nope")) {
            _ = try await registry.perform("nope")
        }
    }

    @Test func unregisterRemovesOnlyThatFeaturesActions() {
        registry.register([FeatureAction(id: "a.x", title: "") { _ in .none }], for: "a")
        registry.register([FeatureAction(id: "b.y", title: "") { _ in .none }], for: "b")

        registry.unregisterAll(for: "a")

        #expect(!registry.contains("a.x"))
        #expect(registry.contains("b.y"))
    }
}
