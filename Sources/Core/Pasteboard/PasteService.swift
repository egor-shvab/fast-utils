import AppKit
import Carbon.HIToolbox
import OSLog

/// Sends ⌘V (or ⌘C) to the frontmost app. Abstracted so tests never type into real apps.
@MainActor
public protocol KeystrokeSender: AnyObject {
    /// `false` when it cannot (no Accessibility permission).
    var canSend: Bool { get }
    func send(keyCode: Int, modifiers: CGEventFlags)
}

@MainActor
public final class SystemKeystrokeSender: KeystrokeSender {
    public init() {}

    public var canSend: Bool { AXIsProcessTrusted() }

    public func send(keyCode: Int, modifiers: CGEventFlags) {
        // A virtual key code, not a character: works in any keyboard layout.
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
            event?.flags = modifiers
            event?.post(tap: .cghidEventTap)
        }
    }
}

@MainActor
public final class FakeKeystrokeSender: KeystrokeSender {
    public var canSend = true
    public private(set) var sent: [(keyCode: Int, modifiers: CGEventFlags)] = []
    public init() {}
    public func send(keyCode: Int, modifiers: CGEventFlags) { sent.append((keyCode, modifiers)) }
}

/// Puts content on the clipboard and pastes it into the app the user was in (TZ.md §7.4).
@MainActor
public final class PasteService {
    public enum Outcome: Equatable {
        case pasted
        /// Only copied: auto-paste is off, or there is no Accessibility permission.
        case copied(missingPermission: Bool)
    }

    private let pasteboard: PasteboardService
    private let keystrokes: any KeystrokeSender
    private let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "paste")
    /// Delays are injectable so tests run instantly.
    var focusDelay: Duration = .milliseconds(60)
    var restoreDelay: Duration = .milliseconds(400)

    public init(pasteboard: PasteboardService, keystrokes: any KeystrokeSender = SystemKeystrokeSender()) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
    }

    /// - Parameters:
    ///   - targetApp: the app that was frontmost before our panel appeared.
    ///   - autoPaste: `false` = only copy ("copy, don't paste" setting).
    ///   - restorePrevious: put the previous clipboard back after pasting.
    @discardableResult
    public func paste(
        _ content: PasteboardSnapshot,
        plainText: Bool = false,
        into targetApp: NSRunningApplication?,
        autoPaste: Bool = true,
        restorePrevious: Bool = false
    ) async -> Outcome {
        let previous = restorePrevious ? pasteboard.readSnapshot(bypassingFilter: true) : nil
        pasteboard.write(content, plainTextOnly: plainText)

        guard autoPaste else { return .copied(missingPermission: false) }
        guard keystrokes.canSend else { return .copied(missingPermission: true) }

        // Our panels never activate FastUtils, so the target normally is still frontmost;
        // activate it anyway in case focus moved, then give it a moment.
        if let targetApp, NSWorkspace.shared.frontmostApplication != targetApp {
            targetApp.activate()
        }
        try? await Task.sleep(for: focusDelay)
        keystrokes.send(keyCode: kVK_ANSI_V, modifiers: .maskCommand)
        log.debug("Pasted into \(targetApp?.bundleIdentifier ?? "?", privacy: .public)")

        if let previous {
            try? await Task.sleep(for: restoreDelay)
            pasteboard.write(previous, recordInHistory: false)
        }
        return .pasted
    }
}
