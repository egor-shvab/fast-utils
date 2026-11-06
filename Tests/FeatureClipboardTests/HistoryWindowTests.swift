import AppKit
import Carbon.HIToolbox
import Core
import Testing
@testable import FeatureClipboard

struct HistoryCommandTests {
    private func command(_ key: Int, _ flags: NSEvent.ModifierFlags = [], queryEmpty: Bool = true) -> HistoryCommand {
        HistoryCommand.from(keyCode: key, modifiers: flags, queryIsEmpty: queryEmpty)
    }

    @Test func navigationAndPaste() {
        #expect(command(kVK_UpArrow) == .up)
        #expect(command(kVK_DownArrow) == .down)
        #expect(command(kVK_Return) == .paste)
        #expect(command(kVK_Return, [.shift]) == .pastePlain)
        #expect(command(kVK_Escape) == .escape)
    }

    @Test func quickPasteByPhysicalDigit() {
        #expect(command(kVK_ANSI_1, [.command]) == .quickPaste(1))
        #expect(command(kVK_ANSI_9, [.command]) == .quickPaste(9))
        #expect(command(kVK_ANSI_0, [.command]) == .passThrough)
        #expect(command(kVK_ANSI_1) == .passThrough)  // a plain "1" is typed into search
    }

    @Test func spacePreviewsOnlyWithEmptySearch() {
        #expect(command(kVK_Space, queryEmpty: true) == .preview)
        #expect(command(kVK_Space, queryEmpty: false) == .passThrough)
        #expect(command(kVK_ANSI_Y, [.command], queryEmpty: false) == .preview)
    }

    @Test func itemCommands() {
        #expect(command(kVK_ANSI_C, [.command]) == .copy)
        #expect(command(kVK_ANSI_P, [.command]) == .togglePin)
        #expect(command(kVK_Delete, [.command]) == .delete)
        #expect(command(kVK_Delete) == .passThrough)  // ⌫ edits the search text
        #expect(command(kVK_ANSI_A) == .passThrough)
    }
}

@MainActor
struct HistoryViewModelTests {
    let store: HistoryStore
    let model: HistoryViewModel

    init() throws {
        store = try HistoryStore(directory: temporaryDirectory())
        model = HistoryViewModel(store: store, pageSize: 100)
    }

    private func fill(_ texts: [String]) async throws {
        for (index, text) in texts.enumerated() {
            _ = try await store.add(ClipContent(kind: .text, text: text), sourceBundleID: nil, sourceName: nil,
                                    date: Date(timeIntervalSince1970: 1_000 + Double(index)))
        }
        await model.reload()
    }

    @Test func newestFirstWithFirstSelected() async throws {
        try await fill(["a", "b", "c"])
        #expect(model.ordered.map(\.text) == ["c", "b", "a"])
        #expect(model.selected?.text == "c")
        #expect(model.number(of: model.ordered[2]) == 3)
    }

    @Test func arrowsMoveAndStopAtEdges() async throws {
        try await fill(["a", "b"])
        _ = model.handle(.up)
        #expect(model.selected?.text == "b")
        _ = model.handle(.down)
        _ = model.handle(.down)
        #expect(model.selected?.text == "a")
    }

    @Test func enterAndQuickPasteCallBack() async throws {
        try await fill(["a", "b", "c"])
        var pasted: [(String?, Bool)] = []
        model.onPaste = { item, plain in pasted.append((item.text, plain)) }

        _ = model.handle(.paste)
        _ = model.handle(.pastePlain)
        _ = model.handle(.quickPaste(3))
        _ = model.handle(.quickPaste(9))  // out of range: ignored

        #expect(pasted.map(\.0) == ["c", "c", "a"])
        #expect(pasted.map(\.1) == [false, true, false])
    }

    @Test func escapeClearsSearchThenCloses() async throws {
        try await fill(["кот", "собака"])
        var closed = false
        model.onClose = { closed = true }

        model.query = "кот"
        await model.reload()
        #expect(model.items.map(\.text) == ["кот"])

        _ = model.handle(.escape)
        #expect(model.query.isEmpty && !closed)
        _ = model.handle(.escape)
        #expect(closed)
    }

    @Test func pinnedComeFirstAndFilterWorks() async throws {
        try await fill(["a", "b", "c"])
        await model.setPinned(model.ordered[2], true)  // "a"
        #expect(model.ordered.map(\.text) == ["a", "c", "b"])
        #expect(model.pinnedItems.map(\.text) == ["a"])

        model.filter = .pinned
        await model.reload()
        #expect(model.items.map(\.text) == ["a"])
    }

    @Test func deleteKeepsSelectionPosition() async throws {
        try await fill(["a", "b", "c"])
        _ = model.handle(.down)  // select "b"
        await model.delete(model.selected!)
        #expect(model.ordered.map(\.text) == ["c", "a"])
        #expect(model.selected?.text == "a")
    }

    @Test func loadingThousandItemsIsFast() async throws {
        for i in 0..<1_000 {
            _ = try await store.add(ClipContent(kind: .text, text: "запись номер \(i) " + String(repeating: "текст ", count: 50)),
                                    sourceBundleID: "com.apple.Notes", sourceName: "Заметки")
        }
        let start = ContinuousClock.now
        await model.reload()
        let elapsed = ContinuousClock.now - start
        #expect(model.items.count == 100)  // one page
        let big = HistoryViewModel(store: store, pageSize: 1_000)
        let bigStart = ContinuousClock.now
        await big.reload()
        let bigElapsed = ContinuousClock.now - bigStart
        #expect(big.items.count == 1_000)
        #expect(elapsed < .milliseconds(50), "100 items: \(elapsed)")
        #expect(bigElapsed < .milliseconds(100), "1000 items: \(bigElapsed)")
    }

    @Test func scrollingLoadsMorePagesAndSearchStartsOver() async throws {
        try await fill((0..<250).map { "запись \($0)" })
        #expect(model.items.count == 100)
        #expect(model.canLoadMore)

        await model.loadMore()
        #expect(model.items.count == 200)
        #expect(model.items.first?.text == "запись 249")  // still newest first, the page appended below
        await model.loadMore()
        #expect(model.items.count == 250)
        #expect(!model.canLoadMore)
        await model.loadMore()  // nothing left: no-op
        #expect(model.items.count == 250)

        // Search covers the whole store, not only the loaded pages, and starts from page one.
        model.query = "запись 3"
        await model.reload()
        #expect(model.items.count == 11)  // 3, 30…39
        #expect(!model.canLoadMore)
        model.query = ""
        await model.reload()
        #expect(model.items.count == 100)
    }

    @Test func previewLoadsFullText() async throws {
        let long = String(repeating: "я", count: HistoryStore.listTextLimit + 500)
        try await fill([long])
        #expect(model.ordered.first?.text?.count == HistoryStore.listTextLimit)
        await model.showPreview(model.ordered[0])
        #expect(model.preview?.text?.count == long.count)
    }
}

@MainActor
struct HistoryPasteTests {
    let board = NSPasteboard(name: NSPasteboard.Name("FastUtilsTests.\(UUID().uuidString)"))
    let keys = FakeKeystrokeSender()
    let context: AppContext
    let registry: FeatureRegistry
    var feature: ClipboardFeature { registry.feature("clipboard") as! ClipboardFeature }

    init() {
        context = AppContext.testing(pasteboard: board, keystrokes: keys)
        registry = FeatureRegistry(context: context, types: [ClipboardFeature.self])
    }

    @Test func pastingRichTextRestoresFormatsAndBumpsInsteadOfDuplicating() async throws {
        await registry.startEnabledFeatures()
        let store = try #require(feature.store)
        let rtf = Data("{\\rtf1 жирный}".utf8)
        let added = try await store.add(ClipContent(kind: .text, text: "жирный", rtf: rtf), sourceBundleID: nil, sourceName: nil)
        let listItem = try await store.items().first!

        await feature.paste(listItem, plainText: false, into: nil)

        #expect(board.string(forType: .string) == "жирный")
        #expect(board.data(forType: .rtf) == rtf)
        #expect(keys.sent.count == 1)

        context.pasteboard.checkForChanges()  // the monitor sees our write
        for _ in 0..<50 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(try await store.count() == 1)
        #expect(try await store.items().first?.id == added.item.id)
    }

    @Test func imageAndFilesGoBackOnClipboard() async throws {
        await registry.startEnabledFeatures()
        let store = try #require(feature.store)
        let image = try await store.add(ClipContent(kind: .image, image: makePNG()), sourceBundleID: nil, sourceName: nil).item
        let snapshot = await feature.snapshot(for: image)
        #expect(snapshot?.image?.isEmpty == false)

        let existing = URL(fileURLWithPath: NSTemporaryDirectory())
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID())")
        let files = try await store.add(ClipContent(kind: .files, text: "x", fileURLs: [existing, missing]),
                                        sourceBundleID: nil, sourceName: nil).item
        #expect(await feature.snapshot(for: files)?.fileURLs == [existing])
    }
}
