import AppKit
import Observation

private final class HandlerBox: NSObject {
    let handler: @MainActor () -> Void
    init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
}

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
        statusItem.isVisible = context.preferences.showMenuBarIcon
        observeIndicator()
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        var hasFeatureItems = false
        for feature in registry.features where registry.isEnabled(FeatureRegistry.id(of: feature)) {
            if hasFeatureItems && feature.menuItems.contains(where: { !$0.submenu.isEmpty || $0.actionID == nil }) {
                menu.addItem(.separator())
            }
            for descriptor in feature.menuItems {
                menu.addItem(makeItem(descriptor))
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

    private func makeItem(_ descriptor: MenuItemDescriptor) -> NSMenuItem {
        let item = NSMenuItem(title: descriptor.title, action: nil, keyEquivalent: "")
        item.state = descriptor.isChecked ? .on : .off
        if !descriptor.submenu.isEmpty {
            let submenu = NSMenu()
            descriptor.submenu.forEach { submenu.addItem(makeItem($0)) }
            item.submenu = submenu
        } else if let actionID = descriptor.actionID {
            item.action = #selector(runAction(_:))
            item.target = self
            item.representedObject = actionID.rawValue
            if let shortcut = context.hotkeys.shortcut(for: actionID), let key = shortcut.menuKeyEquivalent {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = shortcut.modifiers.eventFlags
            }
        } else if let handler = descriptor.handler {
            item.action = #selector(runHandler(_:))
            item.target = self
            item.representedObject = HandlerBox(handler)
        }
        item.isEnabled = descriptor.isEnabled && (item.action != nil || item.submenu != nil)
        return item
    }

    @objc private func runHandler(_ sender: NSMenuItem) {
        (sender.representedObject as? HandlerBox)?.handler()
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

    /// Updates the icon when a feature reports a state (e.g. clipboard history paused).
    private func observeIndicator() {
        withObservationTracking {
            _ = context.statusIndicator.symbol
            _ = context.preferences.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyIndicator()
                self?.observeIndicator()
            }
        }
    }

    private func applyIndicator() {
        let symbol = context.statusIndicator.symbol ?? "text.viewfinder"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: AppInfo.name)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = context.statusIndicator.tooltip
        statusItem.isVisible = context.preferences.showMenuBarIcon
    }
    @objc private func showAbout() { openSettings(.about) }
}
