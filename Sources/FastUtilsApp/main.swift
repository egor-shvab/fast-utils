import AppKit
import Core

// Must run before anything is localized: the chosen interface language becomes the
// app's `AppleLanguages`.
InterfaceLanguage.applyStored()

// Agent app: no Dock icon, no main window. `LSUIElement` in Info.plist does the same
// for the bundled app; the activation policy also covers `swift run` without a bundle.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
