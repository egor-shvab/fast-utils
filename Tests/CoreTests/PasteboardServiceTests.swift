import AppKit
import Testing
@testable import Core

@MainActor
struct PasteboardServiceTests {
    let board = NSPasteboard(name: NSPasteboard.Name("FastUtilsTests.\(UUID().uuidString)"))
    let context: AppContext

    init() { context = AppContext.testing(pasteboard: board) }

    @Test func externalChangeIsPublishedWithSnapshot() async {
        var events = context.events.stream(of: ClipboardChanged.self).makeAsyncIterator()
        board.clearContents()
        board.setString("Привет", forType: .string)

        context.pasteboard.checkForChanges()

        let event = await events.next()
        #expect(event?.recordInHistory == true)
        #expect(event?.snapshot.string == "Привет")
        #expect(event?.snapshot.types.contains(NSPasteboard.PasteboardType.string.rawValue) == true)
    }

    @Test func noChangeNoEvent() {
        context.pasteboard.checkForChanges()  // nothing written since init
        // A second check right after must also stay silent; nothing to await — just no crash.
        context.pasteboard.checkForChanges()
    }

    @Test func technicalWriteIsMarkedNotForHistory() async {
        var events = context.events.stream(of: ClipboardChanged.self).makeAsyncIterator()
        context.pasteboard.writeText("restore", recordInHistory: false)
        context.pasteboard.checkForChanges()
        #expect(await events.next()?.recordInHistory == false)

        context.pasteboard.writeText("OCR result")
        context.pasteboard.checkForChanges()
        #expect(await events.next()?.recordInHistory == true)
    }

    @Test func contentsAreNotReadWhenFilterRefuses() async {
        var events = context.events.stream(of: ClipboardChanged.self).makeAsyncIterator()
        context.pasteboard.shouldReadContents = { types, _ in !types.contains("org.nspasteboard.ConcealedType") }
        let item = NSPasteboardItem()
        item.setString("secret", forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        board.clearContents()
        board.writeObjects([item])

        context.pasteboard.checkForChanges()

        let event = await events.next()
        #expect(event?.snapshot.string == nil)
        #expect(event?.snapshot.types.contains("org.nspasteboard.ConcealedType") == true)
    }

    @Test func writeRichSnapshotRoundTrips() {
        let rtf = "{\\rtf1 hi}".data(using: .utf8)!
        context.pasteboard.write(PasteboardSnapshot(string: "hi", rtf: rtf))
        #expect(board.string(forType: .string) == "hi")
        #expect(board.data(forType: .rtf) == rtf)

        context.pasteboard.write(PasteboardSnapshot(string: "hi", rtf: rtf), plainTextOnly: true)
        #expect(board.data(forType: .rtf) == nil)
    }
}
