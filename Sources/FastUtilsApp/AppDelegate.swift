import AppKit
import Core
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "app")
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = makeStatusItem()
        log.notice("Started, version \(AppInfo.version, privacy: .public)")
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        let quit = NSMenuItem(
            title: String(localized: "menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
        item.menu = menu
        return item
    }
}
