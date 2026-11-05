import Testing
@testable import Core

@MainActor
final class ScreenFeature: Feature {
    static let id: FeatureID = "screen"
    init(context: AppContext) {}
    var title: String { "Screen" }
    var icon: String { "display" }
    var requiredPermissions: Set<Permission> { [.screenRecording] }
    var actions: [FeatureAction] { [] }
}

@MainActor
final class PasteFeature: Feature {
    static let id: FeatureID = "paste"
    init(context: AppContext) {}
    var title: String { "Paste" }
    var icon: String { "doc.on.clipboard" }
    var requiredPermissions: Set<Permission> { [.accessibility, .pasteboard] }
    var actions: [FeatureAction] { [] }
}

@MainActor
struct PermissionsTests {
    let checker = FakePermissionChecker()
    let context: AppContext

    init() { context = AppContext.testing(permissions: checker) }

    @Test func refreshPicksUpChanges() {
        #expect(!context.permissions.isGranted(.accessibility))
        checker.statuses[.accessibility] = .granted
        context.permissions.refresh()
        #expect(context.permissions.isGranted(.accessibility))
    }

    @Test func requestGoesToCheckerAndRefreshes() {
        checker.statuses[.screenRecording] = .granted  // the system grants it during the request
        context.permissions.request(.screenRecording)
        #expect(checker.requested == [.screenRecording])
        #expect(context.permissions.isGranted(.screenRecording))
    }

    @Test func requiredPermissionsFollowEnabledFeatures() async {
        let registry = FeatureRegistry(context: context, types: [ScreenFeature.self, PasteFeature.self])
        await registry.startEnabledFeatures()
        #expect(registry.requiredPermissions == [.screenRecording, .accessibility, .pasteboard])

        await registry.setEnabled(false, for: "paste")
        #expect(registry.requiredPermissions == [.screenRecording])
    }

    @Test func hudSettingsArePersisted() {
        context.hud.isEnabled = false
        context.hud.position = .nearCursor
        let reloaded = HUDService(settings: context.settings.app)
        #expect(!reloaded.isEnabled)
        #expect(reloaded.position == .nearCursor)
    }
}
