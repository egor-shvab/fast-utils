import AppKit

/// Temporary: shown by stub actions until the real features land (stages 4–7).
@MainActor
public enum StubAlert {
    public static func show(feature: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "stub.title")
        alert.informativeText = String(format: String(localized: "stub.message"), feature)
        NSApp.activate()
        alert.runModal()
    }
}
