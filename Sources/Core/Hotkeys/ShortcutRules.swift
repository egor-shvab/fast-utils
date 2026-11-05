import Carbon.HIToolbox

/// Result of checking a shortcut the user is about to assign.
public enum ShortcutCheck: Equatable, Sendable {
    case ok
    /// Allowed, but the user should know about a clash with macOS or popular apps.
    case warning(String)
    /// Not allowed (duplicate inside FastUtils, or a shortcut that would break typing).
    case blocked(String)
}

enum ShortcutRules {
    /// Taking these globally would break every app, so they are refused.
    static let reserved: [Shortcut: String.LocalizationValue] = [
        Shortcut(kVK_ANSI_C, .command): "shortcut.reserved.copy",
        Shortcut(kVK_ANSI_V, .command): "shortcut.reserved.paste",
        Shortcut(kVK_ANSI_X, .command): "shortcut.reserved.cut",
        Shortcut(kVK_ANSI_Z, .command): "shortcut.reserved.undo",
        Shortcut(kVK_ANSI_Z, [.shift, .command]): "shortcut.reserved.redo",
        Shortcut(kVK_ANSI_A, .command): "shortcut.reserved.selectAll",
        Shortcut(kVK_ANSI_Q, .command): "shortcut.reserved.quit",
        Shortcut(kVK_ANSI_W, .command): "shortcut.reserved.close",
        Shortcut(kVK_Tab, .command): "shortcut.reserved.switchApps",
    ]

    /// Well-known shortcuts of other apps: allowed, with a warning.
    static let known: [Shortcut: String.LocalizationValue] = [
        Shortcut(kVK_ANSI_T, [.shift, .command]): "shortcut.known.reopenTab",
        Shortcut(kVK_ANSI_V, [.shift, .command]): "shortcut.known.pastePlain",
        Shortcut(kVK_ANSI_V, [.option, .command]): "shortcut.known.finderMove",
        Shortcut(kVK_ANSI_T, [.option, .command]): "shortcut.known.finderToolbar",
        Shortcut(kVK_ANSI_T, .command): "shortcut.known.newTab",
        Shortcut(kVK_ANSI_N, .command): "shortcut.known.newWindow",
        Shortcut(kVK_ANSI_S, .command): "shortcut.known.save",
        Shortcut(kVK_ANSI_F, .command): "shortcut.known.find",
        Shortcut(kVK_ANSI_P, .command): "shortcut.known.print",
        Shortcut(kVK_ANSI_O, .command): "shortcut.known.open",
        Shortcut(kVK_ANSI_H, .command): "shortcut.known.hide",
        Shortcut(kVK_ANSI_M, .command): "shortcut.known.minimize",
        Shortcut(kVK_ANSI_Comma, .command): "shortcut.known.preferences",
    ]

    static func check(_ shortcut: Shortcut, conflictingTitle: String?, systemShortcuts: Set<Shortcut>) -> ShortcutCheck {
        if let conflictingTitle {
            return .blocked(String(format: String(localized: "shortcut.check.duplicate"), conflictingTitle))
        }
        if let key = reserved[shortcut] {
            return .blocked(String(format: String(localized: "shortcut.check.reserved"), String(localized: key)))
        }
        if systemShortcuts.contains(shortcut) {
            return .warning(String(localized: "shortcut.check.system"))
        }
        if let key = known[shortcut] {
            return .warning(String(format: String(localized: "shortcut.check.known"), String(localized: key)))
        }
        return .ok
    }

    /// Enabled system shortcuts from System Settings → Keyboard → Shortcuts
    /// (Spotlight, screenshots, Mission Control, input source switching…).
    static func systemShortcuts() -> Set<Shortcut> {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let entries = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return [] }
        var result = Set<Shortcut>()
        for entry in entries {
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int,
                  code != 0xFFFF else { continue }
            result.insert(Shortcut(code, Shortcut.Modifiers(carbon: modifiers)))
        }
        return result
    }
}
