import Testing
import Core
@testable import FeatureOCR

@MainActor
@Test func registersItsActions() async {
    let context = AppContext.testing()
    let registry = FeatureRegistry(context: context, types: [OCRFeature.self])
    await registry.startEnabledFeatures()

    #expect(registry.isEnabled("ocr"))
    #expect(context.actions.contains("ocr.captureText"))
}
