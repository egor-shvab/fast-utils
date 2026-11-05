import AppKit
import Core

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let context = AppContext()
    private lazy var registry = FeatureRegistry(context: context, types: featureTypes)
    private lazy var settingsWindow = SettingsWindowController(registry: registry, context: context)
    private lazy var onboarding = OnboardingWindowController(registry: registry, context: context)
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        menuBar = MenuBarController(registry: registry, context: context) { [weak self] tab in
            self?.settingsWindow.show(tab: tab)
        }
        Task {
            await registry.startEnabledFeatures()
            context.logger("app").notice("Started, version \(AppInfo.version, privacy: .public)")
            onboarding.showIfNeeded()
        }
    }

    /// Re-opening the app (Finder, Spotlight) while it runs shows Settings —
    /// the way back if the menu bar icon is hidden (TZ.md §4).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }
}
