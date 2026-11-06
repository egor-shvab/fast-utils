import AppKit
import Core
import Testing
@testable import FeatureClipboard

struct ColorParserTests {
    @Test func parsesCommonForms() {
        #expect(ColorParser.parse("#FF0000") == .init(red: 1, green: 0, blue: 0, alpha: 1))
        #expect(ColorParser.parse(" #0f0 ") == .init(red: 0, green: 1, blue: 0, alpha: 1))
        #expect(ColorParser.parse("#0000ff80")?.alpha == Double(0x80) / 255)
        #expect(ColorParser.parse("rgb(255, 255, 255)") == .init(red: 1, green: 1, blue: 1, alpha: 1))
        #expect(ColorParser.parse("rgba(0, 0, 0, 0.5)")?.alpha == 0.5)
    }

    @Test func ignoresOtherText() {
        #expect(ColorParser.parse("#hashtag") == nil)
        #expect(ColorParser.parse("FF0000") == nil)
        #expect(ColorParser.parse("#12345") == nil)
        #expect(ColorParser.parse("rgb(300, 0, 0)") == nil)
    }
}

/// Another feature offering an action on text (stands in for Translate).
@MainActor
final class ShoutFeature: Feature {
    static let id: FeatureID = "shout"
    static var received: String?
    init(context: AppContext) {}
    var title: String { "Shout" }
    var icon: String { "speaker" }
    var actions: [FeatureAction] {
        [FeatureAction(id: "shout.upper", title: "Upper", isInternal: true, accepts: [.text], contentTitle: "UPPER") { input in
            guard case .text(let text) = input else { return .none }
            ShoutFeature.received = text
            return .text(text.uppercased())
        }]
    }
}

@MainActor
struct HistoryContentActionTests {
    let board = NSPasteboard(name: NSPasteboard.Name("FastUtilsTests.\(UUID().uuidString)"))
    let context: AppContext
    let registry: FeatureRegistry
    var feature: ClipboardFeature { registry.feature("clipboard") as! ClipboardFeature }

    init() {
        context = AppContext.testing(pasteboard: board)
        registry = FeatureRegistry(context: context, types: [ClipboardFeature.self, ShoutFeature.self])
    }

    @Test func otherFeaturesActionsAppearAndRunOnFullText() async throws {
        await registry.startEnabledFeatures()
        let store = try #require(feature.store)
        let long = "начало " + String(repeating: "x", count: HistoryStore.listTextLimit)
        _ = try await store.add(ClipContent(kind: .text, text: long), sourceBundleID: nil, sourceName: nil)
        let item = try await store.items().first!

        let actions = feature.contentActions(for: item)
        #expect(actions.map(\.contentTitle) == ["UPPER"])

        await feature.run(actions[0], on: item)
        #expect(ShoutFeature.received == long)  // full text, not the truncated list version
        #expect(board.string(forType: .string) == long.uppercased())
    }

    @Test func filesGetNoContentActions() async throws {
        await registry.startEnabledFeatures()
        let store = try #require(feature.store)
        let item = try await store.add(ClipContent(kind: .files, text: "a", fileURLs: [URL(fileURLWithPath: "/tmp/a")]),
                                       sourceBundleID: nil, sourceName: nil).item
        #expect(feature.contentActions(for: item).isEmpty)
    }

    @Test func sidePreviewFollowsSelection() async throws {
        await registry.startEnabledFeatures()
        let store = try #require(feature.store)
        _ = try await store.add(ClipContent(kind: .text, text: "первая"), sourceBundleID: nil, sourceName: nil,
                                date: Date(timeIntervalSince1970: 1))
        _ = try await store.add(ClipContent(kind: .text, text: "вторая"), sourceBundleID: nil, sourceName: nil,
                                date: Date(timeIntervalSince1970: 2))
        let model = HistoryViewModel(store: store, pageSize: 10)
        model.previewOnSelect = true
        await model.reload()
        _ = model.handle(.down)
        for _ in 0..<50 where model.sidePreview?.text != "первая" { await Task.yield() }
        #expect(model.sidePreview?.text == "первая")
    }
}
