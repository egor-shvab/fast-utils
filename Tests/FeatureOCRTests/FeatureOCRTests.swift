import Testing
@testable import FeatureOCR

@Test func moduleHasID() {
    #expect(!FeatureOCRModule.id.isEmpty)
}
