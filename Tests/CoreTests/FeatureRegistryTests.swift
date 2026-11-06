import Testing
@testable import Core

@MainActor
final class AlphaFeature: Feature {
    static let id: FeatureID = "alpha"
    var starts = 0
    var stops = 0
    init(context: AppContext) {}
    var title: String { "Alpha" }
    var icon: String { "a.circle" }
    var actions: [FeatureAction] { [FeatureAction(id: "alpha.run", title: "Run") { _ in .text("alpha") }] }
    func start() async { starts += 1 }
    func stop() async { stops += 1 }
}

@MainActor
final class BetaFeature: Feature {
    static let id: FeatureID = "beta"
    init(context: AppContext) {}
    var title: String { "Beta" }
    var icon: String { "b.circle" }
    var actions: [FeatureAction] { [FeatureAction(id: "beta.run", title: "Run") { _ in .none }] }
}

@MainActor
struct FeatureRegistryTests {
    let context = AppContext.testing()

    func makeRegistry() -> FeatureRegistry {
        FeatureRegistry(context: context, types: [AlphaFeature.self, BetaFeature.self])
    }

    @Test func featuresAreEnabledByDefaultAndRegisterActions() async {
        let registry = makeRegistry()
        await registry.startEnabledFeatures()

        #expect(registry.enabledIDs == ["alpha", "beta"])
        #expect(context.actions.contains("alpha.run"))
        #expect((registry.feature("alpha") as? AlphaFeature)?.starts == 1)
    }

    @Test func disablingStopsFeatureAndRemovesItsActions() async {
        let registry = makeRegistry()
        await registry.startEnabledFeatures()

        await registry.setEnabled(false, for: "alpha")

        #expect(!registry.isEnabled("alpha"))
        #expect(!context.actions.contains("alpha.run"))
        #expect(context.actions.contains("beta.run"))
        #expect((registry.feature("alpha") as? AlphaFeature)?.stops == 1)
    }

    @Test func enabledStateIsPersisted() async {
        let first = makeRegistry()
        await first.startEnabledFeatures()
        await first.setEnabled(false, for: "beta")

        // Same settings, fresh registry — like an app restart.
        let second = makeRegistry()
        await second.startEnabledFeatures()
        #expect(second.enabledIDs == ["alpha"])
    }

    @Test func togglingTwiceDoesNotStartTwice() async {
        let registry = makeRegistry()
        await registry.startEnabledFeatures()
        await registry.setEnabled(true, for: "alpha")

        #expect((registry.feature("alpha") as? AlphaFeature)?.starts == 1)
    }

    @Test func crossFeatureActionCall() async throws {
        let registry = makeRegistry()
        await registry.startEnabledFeatures()

        let output = try await context.actions.perform("alpha.run")
        guard case .text(let s) = output else { Issue.record("expected text"); return }
        #expect(s == "alpha")
    }
}
