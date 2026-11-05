import Testing
@testable import FeatureTranslate

@Test func moduleHasID() {
    #expect(!FeatureTranslateModule.id.isEmpty)
}
