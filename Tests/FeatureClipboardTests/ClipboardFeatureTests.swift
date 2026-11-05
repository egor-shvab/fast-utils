import Testing
import Core
@testable import FeatureClipboard

@MainActor
@Test func registersItsActions() async {
    let context = AppContext.testing()
    let registry = FeatureRegistry(context: context, types: [ClipboardFeature.self])
    await registry.startEnabledFeatures()

    #expect(registry.isEnabled("clipboard"))
    #expect(context.actions.contains("clipboard.showHistory"))
}
