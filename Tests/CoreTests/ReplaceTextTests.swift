import AppKit
import Carbon.HIToolbox
import Testing
@testable import Core

/// A one-line text field driven by the keys `replaceSelectionOrLastWord` sends.
@MainActor
final class FakeTextField {
    var text: [Character]
    var caret: Int
    /// Selected range, anchored at its end (the caret side for ⇧←).
    var selection: Range<Int>
    var copiesLineWithoutSelection = false

    init(_ text: String, selecting range: Range<Int>? = nil) {
        self.text = Array(text)
        caret = range?.upperBound ?? text.count
        selection = range ?? caret..<caret
    }

    var string: String { String(text) }

    func handle(_ keyCode: Int, _ modifiers: CGEventFlags, board: NSPasteboard) {
        let command = modifiers.contains(.maskCommand)
        let shift = modifiers.contains(.maskShift)
        switch keyCode {
        case kVK_LeftArrow where command && shift:
            selection = 0..<caret
        case kVK_LeftArrow where shift:
            let start = selection.isEmpty ? caret : selection.lowerBound
            selection = max(start - 1, 0)..<caret
        case kVK_RightArrow:
            if selection.isEmpty { caret = min(caret + 1, text.count) } else { caret = selection.upperBound }
            selection = caret..<caret
        case kVK_ANSI_C where command:
            if !selection.isEmpty {
                board.clearContents()
                board.setString(String(text[selection]), forType: .string)
            } else if copiesLineWithoutSelection {
                board.clearContents()
                board.setString(string + "\n", forType: .string)
            }
        case kVK_ANSI_V where command:
            let pasted = Array(board.string(forType: .string) ?? "")
            text.replaceSubrange(selection, with: pasted)
            caret = selection.lowerBound + pasted.count
            selection = caret..<caret
        default:
            break
        }
    }
}

@MainActor
struct ReplaceTextTests {
    let board = NSPasteboard(name: NSPasteboard.Name("FastUtilsTests.\(UUID().uuidString)"))
    let keys = FakeKeystrokeSender()
    let context: AppContext

    init() {
        context = AppContext.testing(pasteboard: board, keystrokes: keys)
        board.clearContents()
        board.setString("буфер пользователя", forType: .string)
        context.pasteboard.checkForChanges()
    }

    private func attach(_ field: FakeTextField, probe: Bool? = nil) {
        context.paste.selectionProbe = { probe ?? !field.selection.isEmpty }
        keys.onSend = { [keys, board] code in
            field.handle(code, keys.sent.last?.modifiers ?? [], board: board)
        }
    }

    @Test func replacesTheSelection() async {
        let field = FakeTextField("say hello world", selecting: 4..<9)
        attach(field)
        let outcome = await context.paste.replaceSelectionOrLastWord { $0.uppercased() }
        #expect(outcome == .replaced)
        #expect(field.string == "say HELLO world")
        #expect(board.string(forType: .string) == "буфер пользователя")
    }

    @Test func replacesTheWordBeforeTheCaretKeepingSpaces() async {
        let field = FakeTextField("это kj;rf  ")
        attach(field)
        let outcome = await context.paste.replaceSelectionOrLastWord { $0.uppercased() }
        #expect(outcome == .replaced)
        #expect(field.string == "это KJ;RF  ")
        #expect(field.caret == field.text.count)
        #expect(board.string(forType: .string) == "буфер пользователя")
    }

    @Test func emptyLineReplacesNothingAndLeavesTheCaret() async {
        let field = FakeTextField("")
        attach(field)
        #expect(await context.paste.replaceSelectionOrLastWord { $0.uppercased() } == .nothingToReplace)
        #expect(field.caret == 0)
    }

    @Test func unchangedWordIsLeftAlone() async {
        let field = FakeTextField("abc 123")
        attach(field)
        #expect(await context.paste.replaceSelectionOrLastWord { $0 } == .nothingToReplace)
        #expect(field.string == "abc 123")
        #expect(!keys.sent.contains { $0.keyCode == kVK_ANSI_V })
    }

    /// VS Code copies the whole line on ⌘C with no selection; when the app does not report the
    /// selection, the line must not be pasted a second time.
    @Test func lineCopiedWithoutSelectionIsNotPasted() async {
        let field = FakeTextField("")
        field.copiesLineWithoutSelection = true
        field.text = Array("hello")
        field.caret = 0
        field.selection = 0..<0
        attach(field, probe: false)
        #expect(await context.paste.replaceSelectionOrLastWord { $0.uppercased() } == .nothingToReplace)
        #expect(field.string == "hello")
    }

    @Test func withoutAccessibilityNothingIsSent() async {
        keys.canSend = false
        #expect(await context.paste.replaceSelectionOrLastWord { $0 } == .missingPermission)
        #expect(keys.sent.isEmpty)
    }

    @Test func historyRecordsNothing() async {
        let field = FakeTextField("ghbdtn")
        attach(field)
        var events = context.events.stream(of: ClipboardChanged.self).makeAsyncIterator()
        await context.paste.replaceSelectionOrLastWord { $0.uppercased() }
        board.clearContents()
        board.setString("потом", forType: .string)
        context.pasteboard.checkForChanges()
        #expect(await events.next()?.snapshot.string == "потом")  // the first event is the user's copy
    }

    @Test(arguments: [
        ("foo ghbdtn  ", "ghbdtn", "  "),
        ("kj;rf", "kj;rf", ""),
        ("a\tb", "b", ""),
    ])
    func lastWord(_ line: String, _ word: String, _ trailing: String) {
        let split = LastWord.split(line)
        #expect(split?.word == word)
        #expect(split?.trailing == trailing)
    }

    @Test func noLastWordInBlankText() {
        #expect(LastWord.split("") == nil)
        #expect(LastWord.split("   ") == nil)
    }
}
