import AppKit
import Carbon.HIToolbox
import Testing
@testable import Core

@MainActor
struct ContentActionTests {
    @Test func actionsAreFoundByInputKindExcludingOwnFeature() {
        let registry = ActionRegistry()
        registry.register([FeatureAction(id: "t.show", title: "", accepts: [.text], contentTitle: "Translate") { _ in .none }], for: "t")
        registry.register([FeatureAction(id: "o.image", title: "", accepts: [.image]) { _ in .none }], for: "o")
        registry.register([FeatureAction(id: "c.own", title: "", accepts: [.text]) { _ in .none }], for: "c")

        #expect(registry.actions(accepting: .text, excluding: "c").map(\.id) == ["t.show"])
        #expect(registry.actions(accepting: .image).map(\.id) == ["o.image"])
        #expect(ActionInput.text("x").kind == .text)
    }
}

@MainActor
struct CopySelectionTests {
    let board = NSPasteboard(name: NSPasteboard.Name("FastUtilsTests.\(UUID().uuidString)"))
    let keys = FakeKeystrokeSender()
    let context: AppContext

    init() {
        context = AppContext.testing(pasteboard: board, keystrokes: keys)
        board.clearContents()
        board.setString("было в буфере", forType: .string)
        context.pasteboard.checkForChanges()
    }

    @Test func returnsSelectionAndRestoresClipboardWithoutHistory() async {
        keys.onSend = { [board] key in
            guard key == kVK_ANSI_C else { return }
            board.clearContents()
            board.setString("выделенный текст", forType: .string)
        }
        var events = context.events.stream(of: ClipboardChanged.self).makeAsyncIterator()

        let selected = await context.paste.copySelection()

        #expect(selected == "выделенный текст")
        #expect(board.string(forType: .string) == "было в буфере")
        #expect(keys.sent.first?.keyCode == kVK_ANSI_C)
        // The monitor skipped everything that happened meanwhile.
        board.clearContents()
        board.setString("следующее копирование", forType: .string)
        context.pasteboard.checkForChanges()
        #expect(await events.next()?.snapshot.string == "следующее копирование")
    }

    @Test func nothingSelectedLeavesClipboardAlone() async {
        let selected = await context.paste.copySelection()
        #expect(selected == nil)
        #expect(board.string(forType: .string) == "было в буфере")
    }

    @Test func nonTextSelectionStillRestoresClipboard() async {
        let custom = NSPasteboard.PasteboardType("com.example.private-format")
        let item = NSPasteboardItem()
        item.setString("было в буфере", forType: .string)
        item.setData(Data([7, 7]), forType: custom)
        board.clearContents()
        board.writeObjects([item])
        keys.onSend = { [board] key in
            guard key == kVK_ANSI_C else { return }
            board.clearContents()
            board.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)  // the app copied an image
        }

        #expect(await context.paste.copySelection() == nil)
        #expect(board.string(forType: .string) == "было в буфере")
        #expect(board.data(forType: custom) == Data([7, 7]))
        #expect(board.data(forType: .png) == nil)
    }

    @Test func concealedSelectionIsNotReturned() async {
        keys.onSend = { [board] key in
            guard key == kVK_ANSI_C else { return }
            let item = NSPasteboardItem()
            item.setString("hunter2", forType: .string)
            item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            board.clearContents()
            board.writeObjects([item])
        }
        #expect(await context.paste.copySelection() == nil)
        #expect(board.string(forType: .string) == "было в буфере")
    }

    @Test func noAccessibilityNoAttempt() async {
        keys.canSend = false
        #expect(await context.paste.copySelection() == nil)
        #expect(keys.sent.isEmpty)
    }
}

@MainActor
struct SettingsBackupTests {
    @Test func exportImportRoundTripSkipsForeignKeys() throws {
        let source = AppContext.testing()
        source.settings.scoped("ocr").set(["ru", "en"], for: "languages")
        source.settings.scoped("hotkeys").set(["keyCode": 17, "modifiers": 10], for: "translate.clipboard")
        source.settings.app.set(false, for: "hud.enabled")
        let json = try source.settings.exportJSON()
        let text = String(decoding: json, as: UTF8.self)
        #expect(text.contains("ocr.languages"))
        #expect(!text.contains("NSLanguages"))  // only FastUtils keys

        let target = AppContext.testing()
        let applied = try target.settings.importJSON(json)
        #expect(applied >= 3)
        #expect(target.settings.scoped("ocr").value("languages", default: [String]()) == ["ru", "en"])
        #expect(target.settings.app.value("hud.enabled", default: true) == false)
        #expect(target.settings.scoped("hotkeys").rawValue("translate.clipboard") as? [String: Int] == ["keyCode": 17, "modifiers": 10])
    }

    @Test func garbageIsRejected() {
        #expect(throws: (any Error).self) { try AppContext.testing().settings.importJSON(Data("[1,2]".utf8)) }
    }

    @Test func windowRectsAreFlipped() {
        let rect = AreaSelectionService.flipToAppKit(CGRect(x: 10, y: 0, width: 100, height: 50), primaryHeight: 900)
        #expect(rect == CGRect(x: 10, y: 850, width: 100, height: 50))
    }
}
