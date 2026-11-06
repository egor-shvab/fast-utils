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

    private func write(_ text: String, extraTypes: [String: String] = [:]) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        for (type, value) in extraTypes { item.setString(value, forType: NSPasteboard.PasteboardType(type)) }
        board.clearContents()
        board.writeObjects([item])
    }

    @Test func passwordContentsAreNotRead() async {
        var events = context.events.stream(of: ClipboardChanged.self).makeAsyncIterator()
        write("secret", extraTypes: ["org.nspasteboard.ConcealedType": ""])

        context.pasteboard.checkForChanges()

        let event = await events.next()
        #expect(event?.snapshot.string == nil)
        #expect(event?.snapshot.contentsWithheld == true)
        #expect(event?.snapshot.types.contains("org.nspasteboard.ConcealedType") == true)
    }

    @Test func monitorMayReadPasswordsWhenHistoryAllowsIt() async {
        var events = context.events.stream(of: ClipboardChanged.self).makeAsyncIterator()
        context.pasteboard.monitorReadsConcealed = true
        write("secret", extraTypes: ["org.nspasteboard.ConcealedType": ""])
        context.pasteboard.checkForChanges()
        #expect(await events.next()?.snapshot.string == "secret")
    }

    @Test func featuresNeverGetPasswordText() {
        write("secret", extraTypes: ["org.nspasteboard.ConcealedType": ""])
        context.pasteboard.monitorReadsConcealed = true  // a history setting; it does not open text to features
        #expect(context.pasteboard.containsConcealed)
        #expect(context.pasteboard.readText() == nil)

        write("обычный текст")
        #expect(!context.pasteboard.containsConcealed)
        #expect(context.pasteboard.readText() == "обычный текст")
    }

    @Test func sourceMarkWinsOverFrontmostAppAndExcludesIt() async {
        var events = context.events.stream(of: ClipboardChanged.self).makeAsyncIterator()
        context.pasteboard.excludedApps = ["com.example.vault"]

        write("из хранилища", extraTypes: ["org.nspasteboard.source": "com.example.vault"])
        context.pasteboard.checkForChanges()
        let excluded = await events.next()?.snapshot
        #expect(excluded?.sourceBundleID == "com.example.vault")
        #expect(excluded?.contentsWithheld == true)
        #expect(excluded?.string == nil)

        write("из заметок", extraTypes: ["org.nspasteboard.source": "com.example.notes"])
        context.pasteboard.checkForChanges()
        let allowed = await events.next()?.snapshot
        #expect(allowed?.sourceBundleID == "com.example.notes")
        #expect(allowed?.string == "из заметок")
    }

    @Test func imageDataIsSkippedWhenHistoryKeepsNoImages() async {
        var events = context.events.stream(of: ClipboardChanged.self).makeAsyncIterator()
        context.pasteboard.monitorReadsImages = false
        board.clearContents()
        board.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        context.pasteboard.checkForChanges()
        let snapshot = await events.next()?.snapshot
        #expect(snapshot?.image == nil)
        #expect(snapshot?.types.contains("public.png") == true)
    }

    @Test func backupRestoresEveryItemAndType() async {
        let custom = NSPasteboard.PasteboardType("com.example.private-format")
        let first = NSPasteboardItem()
        first.setString("первый", forType: .string)
        first.setData(Data([1, 2, 3]), forType: custom)
        let second = NSPasteboardItem()
        second.setString("второй", forType: .string)
        board.clearContents()
        board.writeObjects([first, second])
        context.pasteboard.checkForChanges()
        let backup = context.pasteboard.backup()

        context.pasteboard.writeText("что-то другое")
        var events = context.events.stream(of: ClipboardChanged.self).makeAsyncIterator()
        context.pasteboard.restore(backup)

        let items = board.pasteboardItems ?? []
        #expect(items.count == 2)
        #expect(items.first?.string(forType: .string) == "первый")
        #expect(items.first?.data(forType: custom) == Data([1, 2, 3]))
        #expect(items.last?.string(forType: .string) == "второй")
        context.pasteboard.checkForChanges()
        #expect(await events.next()?.recordInHistory == false)
    }

    @Test func emptyBackupRestoresEmptyClipboard() {
        board.clearContents()
        let backup = context.pasteboard.backup()
        context.pasteboard.writeText("временное")
        context.pasteboard.restore(backup)
        #expect(board.pasteboardItems?.isEmpty ?? true)
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
