import AppKit

/// The status bar icon and its menu. The menu is rebuilt each time it opens, so it always
/// reflects which features are enabled.
@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let registry: FeatureRegistry
    private let context: AppContext
    private let openSettings: (SettingsTab) -> Void

    public init(registry: FeatureRegistry, context: AppContext, openSettings: @escaping (SettingsTab) -> Void) {
        self.registry = registry
        self.context = context
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        var hasFeatureItems = false
        for feature in registry.features where registry.isEnabled(FeatureRegistry.id(of: feature)) {
            for descriptor in feature.menuItems {
                let item = NSMenuItem(title: descriptor.title, action: #selector(runAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = descriptor.actionID.rawValue
                if let shortcut = context.hotkeys.shortcut(for: descriptor.actionID),
                   let key = shortcut.menuKeyEquivalent {
                    item.keyEquivalent = key
                    item.keyEquivalentModifierMask = shortcut.modifiers.eventFlags
                }
                menu.addItem(item)
                hasFeatureItems = true
            }
        }
        if !hasFeatureItems {
            let item = NSMenuItem(title: String(localized: "menu.noFeatures"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: String(localized: "menu.settings"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: String(localized: "menu.about"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "menu.quit"),
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let id = ActionID(raw)
        let log = context.logger("menu")
        let actions = context.actions
        Task {
            do {
                try await actions.perform(id)
            } catch {
                log.error("Action \(id.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    @objc private func showSettings() { openSettings(.general) }
    @objc private func showAbout() { openSettings(.about) }
}
