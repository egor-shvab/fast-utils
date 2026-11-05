import Testing
@testable import Core

@Test func bundleIdentifierIsStable() {
    // Changing the bundle id makes macOS ask for all permissions again.
    #expect(AppInfo.bundleIdentifier == "com.yahor.FastUtils")
}
