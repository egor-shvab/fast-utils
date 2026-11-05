import Testing
import Core
@testable import FeatureTranslate

@MainActor
@Test func registersItsActions() async {
    let context = AppContext.testing()
    let registry = FeatureRegistry(context: context, types: [TranslateFeature.self])
    await registry.startEnabledFeatures()

    #expect(registry.isEnabled("translate"))
    #expect(context.actions.contains("translate.clipboard"))
}
