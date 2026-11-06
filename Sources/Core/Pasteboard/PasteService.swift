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

/// Puts content on the clipboard and pastes it into the app the user was in.
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

    /// Copies the selected text of the frontmost app (⌘C) and puts the previous clipboard back
    /// exactly as it was (every item and type). Leaves no trace in clipboard history. `nil` when
    /// nothing is selected, the selection is not text or is concealed, or there is no
    /// Accessibility permission.
    public func copySelection() async -> String? {
        guard keystrokes.canSend else { return nil }
        await waitForModifierRelease()
        pasteboard.suspendMonitoring()
        defer { pasteboard.resumeMonitoring() }
        let text = await copyRaw()
        return text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? text : nil
    }

    /// The user may still hold the hotkey's ⌥/⌘: wait for release so the app gets clean keys.
    private func waitForModifierRelease() async {
        for _ in 0..<25 where !NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// ⌘C and the text the app put on the clipboard (whitespace too), then the previous
    /// clipboard back. `nil`: the clipboard did not change (nothing selected) or holds no text.
    /// The caller suspends monitoring.
    private func copyRaw() async -> String? {
        let previous = pasteboard.backup()
        let before = pasteboard.changeCount
        keystrokes.send(keyCode: kVK_ANSI_C, modifiers: .maskCommand)
        for _ in 0..<Int(selectionTimeout / .milliseconds(20)) {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != before {
                let text = pasteboard.readText()
                // Whatever the app put there (text, an image, a file), the user's clipboard comes back.
                pasteboard.restore(previous)
                return text
            }
        }
        return nil
    }

    public enum ReplaceOutcome: Equatable, Sendable {
        case replaced
        /// No selection and no word before the caret, or the transform changed nothing.
        case nothingToReplace
        case missingPermission
    }

    /// Whether the focused text field has a selection; `nil` = the app does not say.
    /// Replaced in tests.
    var selectionProbe: @MainActor () -> Bool? = { TextCaret.hasSelection() }

    /// Replaces the selected text — or, with nothing selected, the word before the caret —
    /// with `transform(text)`, keeping the user's clipboard and leaving no trace in history.
    ///
    /// The word: ⌘⇧← selects to the line start, the text is copied, the last run without
    /// whitespace is taken (so `kj;rf` stays one word), → collapses the selection back to the
    /// caret and ⇧← selects just that run. Whitespace after it stays as it was.
    public func replaceSelectionOrLastWord(_ transform: (String) -> String) async -> ReplaceOutcome {
        guard keystrokes.canSend else { return .missingPermission }
        await waitForModifierRelease()
        pasteboard.suspendMonitoring()
        defer { pasteboard.resumeMonitoring() }

        // Without asking first, editors that copy the whole line on ⌘C with no selection
        // (VS Code, JetBrains) would get the line converted and pasted a second time.
        let hasSelection = selectionProbe()
        if hasSelection != false, let selected = await copyRaw(),
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let result = transform(selected)
            guard result != selected else { return .nothingToReplace }
            await pasteReplacement(result)
            return .replaced
        }
        if hasSelection == true { return .nothingToReplace }  // a selection, but not text

        send(kVK_LeftArrow, [.maskCommand, .maskShift])
        // Nothing copied: the caret was at the line start and nothing got selected. A newline:
        // the app copied a whole line without a selection. Either way there is nothing to undo.
        guard let line = await copyRaw(), !line.contains(where: \.isNewline) else { return .nothingToReplace }
        send(kVK_RightArrow, [])  // back to the caret
        guard let (word, trailing) = LastWord.split(line) else { return .nothingToReplace }
        let result = transform(word)
        guard result != word else { return .nothingToReplace }
        for _ in 0..<(word.count + trailing.count) { send(kVK_LeftArrow, [.maskShift]) }
        await pasteReplacement(result + trailing)
        return .replaced
    }

    /// Arrow keys as a real keyboard sends them (with the function and keypad flags).
    private func send(_ keyCode: Int, _ modifiers: CGEventFlags) {
        let arrows = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
        let flags = arrows.contains(keyCode) ? modifiers.union([.maskSecondaryFn, .maskNumericPad]) : modifiers
        keystrokes.send(keyCode: keyCode, modifiers: flags)
    }

    /// Pastes over the current selection and puts the user's clipboard back.
    private func pasteReplacement(_ text: String) async {
        let previous = pasteboard.backup()
        pasteboard.writeText(text, recordInHistory: false)
        keystrokes.send(keyCode: kVK_ANSI_V, modifiers: .maskCommand)
        try? await Task.sleep(for: restoreDelay)
        pasteboard.restore(previous)
    }

    /// How long to wait for the app to put the selection on the clipboard.
    var selectionTimeout: Duration = .milliseconds(300)

    /// - Parameters:
    ///   - targetApp: the app that was frontmost before our panel appeared.
    ///   - autoPaste: `false` = only copy ("copy, don't paste" setting).
    ///   - restorePrevious: put the previous clipboard back (all items and types) after pasting.
    @discardableResult
    public func paste(
        _ content: PasteboardSnapshot,
        plainText: Bool = false,
        into targetApp: NSRunningApplication?,
        autoPaste: Bool = true,
        restorePrevious: Bool = false
    ) async -> Outcome {
        let previous = restorePrevious ? pasteboard.backup() : nil
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
            pasteboard.restore(previous)
        }
        return .pasted
    }
}

/// The word before the caret, for `replaceSelectionOrLastWord`.
enum LastWord {
    /// The last run of non-whitespace characters in `line` and the whitespace after it;
    /// `nil` if there is none.
    static func split(_ line: String) -> (word: String, trailing: String)? {
        let trailingStart = line.lastIndex { !$0.isWhitespace }.map(line.index(after:)) ?? line.startIndex
        guard trailingStart > line.startIndex else { return nil }
        let head = line[..<trailingStart]
        let wordStart = head.lastIndex(where: \.isWhitespace).map(head.index(after:)) ?? head.startIndex
        return (String(head[wordStart...]), String(line[trailingStart...]))
    }
}
