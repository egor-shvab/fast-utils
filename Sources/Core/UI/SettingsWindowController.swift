import AppKit
import SwiftUI

/// Settings tabs. Feature tabs are identified by the feature id.
public enum SettingsTab: Hashable {
    case general
    case feature(FeatureID)
    case about
}

@MainActor
@Observable
final class SettingsNavigation {
    var selectedTab: SettingsTab = .general
}

/// The Settings window, hosted in AppKit because the app uses an AppKit lifecycle.
@MainActor
public final class SettingsWindowController {
    private let registry: FeatureRegistry
    private let context: AppContext
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    public init(registry: FeatureRegistry, context: AppContext) {
        self.registry = registry
        self.context = context
    }

    public func show(tab: SettingsTab = .general) {
        navigation.selectedTab = tab
        let window = self.window ?? makeWindow()
        self.window = window
        // An agent app is never frontmost by itself; activate so the window gets focus.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsView(registry: registry, context: context, navigation: navigation)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = String(localized: "settings.window.title")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(CGSize(width: 760, height: 560))
        window.contentMinSize = CGSize(width: 680, height: 460)
        window.setFrameAutosaveName("SettingsWindow")
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
