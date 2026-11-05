import AppKit
import Carbon.HIToolbox

/// A key combination bound to a *physical* key (Carbon virtual key code), so it works the
/// same in any keyboard layout (Russian included).
public struct Shortcut: Hashable, Codable, Sendable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        public init(_ flags: NSEvent.ModifierFlags) {
            var result: Modifiers = []
            if flags.contains(.control) { result.insert(.control) }
            if flags.contains(.option) { result.insert(.option) }
            if flags.contains(.shift) { result.insert(.shift) }
            if flags.contains(.command) { result.insert(.command) }
            self = result
        }

        public var eventFlags: NSEvent.ModifierFlags {
            var flags: NSEvent.ModifierFlags = []
            if contains(.control) { flags.insert(.control) }
            if contains(.option) { flags.insert(.option) }
            if contains(.shift) { flags.insert(.shift) }
            if contains(.command) { flags.insert(.command) }
            return flags
        }

        var carbon: UInt32 {
            var value = 0
            if contains(.control) { value |= controlKey }
            if contains(.option) { value |= optionKey }
            if contains(.shift) { value |= shiftKey }
            if contains(.command) { value |= cmdKey }
            return UInt32(value)
        }

        init(carbon: Int) {
            var result: Modifiers = []
            if carbon & controlKey != 0 { result.insert(.control) }
            if carbon & optionKey != 0 { result.insert(.option) }
            if carbon & shiftKey != 0 { result.insert(.shift) }
            if carbon & cmdKey != 0 { result.insert(.command) }
            self = result
        }

        /// Standard macOS order: ⌃⌥⇧⌘.
        public var symbols: String {
            (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
                + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
        }
    }

    /// Carbon virtual key code (`kVK_*` from Carbon.HIToolbox).
    public let keyCode: Int
    public let modifiers: Modifiers

    public init(_ keyCode: Int, _ modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A shortcut from a key press, or `nil` if it cannot be a global shortcut:
    /// it needs ⌘, ⌃ or ⌥ (⇧ alone is not enough), except for F1–F20.
    public init?(event: NSEvent) {
        let modifiers = Modifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        let keyCode = Int(event.keyCode)
        let hasRealModifier = !modifiers.intersection([.command, .control, .option]).isEmpty
        guard hasRealModifier || Self.functionKeys[keyCode] != nil else { return nil }
        self.init(keyCode, modifiers)
    }

    /// "⇧⌘2". Letters are Latin key caps even with a Russian layout, like macOS menus show them.
    public var description: String { modifiers.symbols + keyName }

    public var keyName: String {
        if let name = Self.specialKeys[keyCode] ?? Self.functionKeys[keyCode] { return name }
        return Self.character(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// Value for `NSMenuItem.keyEquivalent` (shown next to menu items).
    public var menuKeyEquivalent: String? {
        if let fIndex = Self.functionKeyOrder.firstIndex(of: keyCode) {
            return String(Character(UnicodeScalar(NSF1FunctionKey + fIndex)!))
        }
        let specials: [Int: Int] = [
            kVK_Return: 0x0D, kVK_Tab: 0x09, kVK_Space: 0x20, kVK_Delete: 0x08, kVK_Escape: 0x1B,
            kVK_ForwardDelete: NSDeleteFunctionKey, kVK_LeftArrow: NSLeftArrowFunctionKey,
            kVK_RightArrow: NSRightArrowFunctionKey, kVK_UpArrow: NSUpArrowFunctionKey,
            kVK_DownArrow: NSDownArrowFunctionKey, kVK_Home: NSHomeFunctionKey, kVK_End: NSEndFunctionKey,
            kVK_PageUp: NSPageUpFunctionKey, kVK_PageDown: NSPageDownFunctionKey,
        ]
        if let scalar = specials[keyCode].flatMap(UnicodeScalar.init) { return String(Character(scalar)) }
        return Self.character(for: keyCode)?.lowercased()
    }

    // MARK: - Key names

    static let functionKeyOrder = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    static let functionKeys: [Int: String] = Dictionary(
        uniqueKeysWithValues: functionKeyOrder.enumerated().map { ($1, "F\($0 + 1)") }
    )

    static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Space: "Space",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    /// Latin key caps of the physical keys (ANSI layout — what macOS menus show for shortcuts).
    /// A static table on purpose: the Text Input Sources API aborts the process when called
    /// from two threads at once, and `description` may be called from any thread.
    static let characters: [Int: String] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d", kVK_ANSI_E: "e", kVK_ANSI_F: "f",
        kVK_ANSI_G: "g", kVK_ANSI_H: "h", kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
        kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p", kVK_ANSI_Q: "q", kVK_ANSI_R: "r",
        kVK_ANSI_S: "s", kVK_ANSI_T: "t", kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
        kVK_ANSI_Y: "y", kVK_ANSI_Z: "z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`", kVK_ISO_Section: "§",
        kVK_ANSI_Keypad0: "0", kVK_ANSI_Keypad1: "1", kVK_ANSI_Keypad2: "2", kVK_ANSI_Keypad3: "3",
        kVK_ANSI_Keypad4: "4", kVK_ANSI_Keypad5: "5", kVK_ANSI_Keypad6: "6", kVK_ANSI_Keypad7: "7",
        kVK_ANSI_Keypad8: "8", kVK_ANSI_Keypad9: "9", kVK_ANSI_KeypadDecimal: ".", kVK_ANSI_KeypadPlus: "+",
        kVK_ANSI_KeypadMinus: "-", kVK_ANSI_KeypadMultiply: "*", kVK_ANSI_KeypadDivide: "/",
        kVK_ANSI_KeypadEquals: "=",
    ]

    static func character(for keyCode: Int) -> String? { characters[keyCode] }
}
