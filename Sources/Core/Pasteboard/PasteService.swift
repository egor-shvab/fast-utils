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
    /// Simulates the target app reacting to a key (e.g. putting the selection on the clipboard).
    public var onSend: ((Int) -> Void)?
    public init() {}
    public func send(keyCode: Int, modifiers: CGEventFlags) {
        sent.append((keyCode, modifiers))
        onSend?(keyCode)
    }
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

    /// Copies the selected text of the frontmost app (⌘C) and puts the previous clipboard back.
    /// Leaves no trace in clipboard history. `nil` when nothing is selected or there is no
    /// Accessibility permission.
    public func copySelection() async -> String? {
        guard keystrokes.canSend else { return nil }
        // The user may still hold the hotkey's ⌥/⌘: wait for release so the app gets a clean ⌘C.
        for _ in 0..<25 where !NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
        pasteboard.suspendMonitoring()
        defer { pasteboard.resumeMonitoring() }

        let previous = pasteboard.readSnapshot(bypassingFilter: true)
        let before = pasteboard.changeCount
        keystrokes.send(keyCode: kVK_ANSI_C, modifiers: .maskCommand)

        var text: String?
        for _ in 0..<Int(selectionTimeout / .milliseconds(20)) {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != before {
                text = pasteboard.readText()
                break
            }
        }
        if text != nil {
            if let previous {
                pasteboard.write(previous, recordInHistory: false)
            } else {
                pasteboard.clear()
            }
        }
        return text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? text : nil
    }

    /// How long to wait for the app to put the selection on the clipboard.
    var selectionTimeout: Duration = .milliseconds(300)

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
