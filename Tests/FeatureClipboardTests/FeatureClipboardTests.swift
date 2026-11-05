import Testing
@testable import FeatureClipboard

@Test func moduleHasID() {
    #expect(!FeatureClipboardModule.id.isEmpty)
}
