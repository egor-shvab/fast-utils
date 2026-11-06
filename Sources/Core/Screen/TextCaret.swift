import AppKit
import ApplicationServices

/// Where the text cursor is in the frontmost app, via Accessibility. Many apps (Electron,
/// games, some web views) do not report it — callers fall back to the mouse pointer.
@MainActor
public enum TextCaret {
    /// How long one Accessibility request may wait for the frontmost app. These calls are
    /// synchronous on the main thread; with the default (~6 s) a hung app froze FastUtils and the
    /// history window did not open. A responsive app answers in a few milliseconds.
    static let messagingTimeout: Float = 0.25

    /// The caret rect in AppKit global coordinates (bottom-left origin), or `nil`.
    public static func rect() -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        // Set on the system-wide element, the timeout applies to every element we query.
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedValue as! AXUIElement

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue
        else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsValue
        ) == .success, let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect != .zero,
              let primary = NSScreen.screens.first
        else { return nil }
        return flipToAppKit(rect, primaryHeight: primary.frame.height)
    }

    /// Accessibility uses a top-left origin at the primary screen's top edge.
    static func flipToAppKit(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
