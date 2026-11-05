import AppKit
import Carbon.HIToolbox
import Testing
@testable import Core

@MainActor
struct PasteServiceTests {
    let board = NSPasteboard(name: NSPasteboard.Name("FastUtilsTests.\(UUID().uuidString)"))
    let keys = FakeKeystrokeSender()
    let context: AppContext

    init() { context = AppContext.testing(pasteboard: board, keystrokes: keys) }

    @Test func writesClipboardAndSendsCommandV() async {
        let outcome = await context.paste.paste(PasteboardSnapshot(string: "вставка"), into: nil)
        #expect(outcome == .pasted)
        #expect(board.string(forType: .string) == "вставка")
        #expect(keys.sent.count == 1)
        #expect(keys.sent.first?.keyCode == kVK_ANSI_V)
        #expect(keys.sent.first?.modifiers == .maskCommand)
    }

    @Test func withoutAccessibilityOnlyCopies() async {
        keys.canSend = false
        let outcome = await context.paste.paste(PasteboardSnapshot(string: "x"), into: nil)
        #expect(outcome == .copied(missingPermission: true))
        #expect(board.string(forType: .string) == "x")
        #expect(keys.sent.isEmpty)
    }

    @Test func copyOnlyMode() async {
        let outcome = await context.paste.paste(PasteboardSnapshot(string: "x"), into: nil, autoPaste: false)
        #expect(outcome == .copied(missingPermission: false))
        #expect(keys.sent.isEmpty)
    }

    @Test func plainTextDropsFormatting() async {
        await context.paste.paste(PasteboardSnapshot(string: "b", rtf: Data("{\\rtf1 b}".utf8)), plainText: true, into: nil)
        #expect(board.string(forType: .string) == "b")
        #expect(board.data(forType: .rtf) == nil)
    }

    @Test func restoresPreviousClipboardWithoutRecordingIt() async {
        board.clearContents()
        board.setString("было", forType: .string)
        context.pasteboard.checkForChanges()
        var events = context.events.stream(of: ClipboardChanged.self).makeAsyncIterator()

        await context.paste.paste(PasteboardSnapshot(string: "вставили"), into: nil, restorePrevious: true)

        #expect(board.string(forType: .string) == "было")
        context.pasteboard.checkForChanges()
        #expect(await events.next()?.recordInHistory == false)
    }

    @Test func caretRectIsFlippedToAppKitCoordinates() {
        let rect = TextCaret.flipToAppKit(CGRect(x: 100, y: 50, width: 2, height: 18), primaryHeight: 900)
        #expect(rect == CGRect(x: 100, y: 832, width: 2, height: 18))
    }
}
