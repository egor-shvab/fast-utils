import AppKit
import Carbon.HIToolbox
import Testing
@testable import Core

struct ShortcutTests {
    @Test func symbolsUseStandardOrder() {
        let all: Shortcut.Modifiers = [.command, .shift, .option, .control]
        #expect(all.symbols == "⌃⌥⇧⌘")
    }

    @Test func specialAndFunctionKeyNames() {
        #expect(Shortcut(kVK_F5, []).description == "F5")
        #expect(Shortcut(kVK_Space, [.option]).description == "⌥Space")
        #expect(Shortcut(kVK_Return, [.command]).keyName == "↩")
    }

    @Test func letterKeysHaveLatinNames() {
        // Comes from the ASCII-capable layout, so it is Latin even with a Russian layout active.
        #expect(Shortcut(kVK_ANSI_T, [.option, .command]).description == "⌥⌘T")
        #expect(Shortcut(kVK_ANSI_2, [.shift, .command]).description == "⇧⌘2")
    }

    @Test func modifiersRoundTripThroughCarbonAndEventFlags() {
        let m: Shortcut.Modifiers = [.command, .option]
        #expect(Shortcut.Modifiers(carbon: Int(m.carbon)) == m)
        #expect(Shortcut.Modifiers(m.eventFlags) == m)
    }

    @MainActor
    @Test func eventWithoutRealModifierIsRejected() throws {
        let shiftOnly = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0,
            context: nil, characters: "A", charactersIgnoringModifiers: "a", isARepeat: false,
            keyCode: UInt16(kVK_ANSI_A)))
        #expect(Shortcut(event: shiftOnly) == nil)

        let f6 = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
            context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
            keyCode: UInt16(kVK_F6)))
        #expect(Shortcut(event: f6) == Shortcut(kVK_F6, []))

        let cmdOpt = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0, windowNumber: 0,
            context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false,
            keyCode: UInt16(kVK_ANSI_V)))
        #expect(Shortcut(event: cmdOpt) == Shortcut(kVK_ANSI_V, [.command, .option]))
    }

    @Test func menuKeyEquivalent() {
        #expect(Shortcut(kVK_ANSI_V, [.option, .command]).menuKeyEquivalent == "v")
        #expect(Shortcut(kVK_F1, []).menuKeyEquivalent == String(Character(UnicodeScalar(NSF1FunctionKey)!)))
    }

    @Test func systemShortcutsCanBeRead() {
        // Real system list; at least Spotlight/screenshots are normally on. Only check it does not crash
        // and parses into shortcuts.
        let shortcuts = ShortcutRules.systemShortcuts()
        #expect(shortcuts.allSatisfy { $0.keyCode >= 0 })
    }
}
