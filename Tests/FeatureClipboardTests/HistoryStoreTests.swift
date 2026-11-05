import Foundation
import Testing
@testable import FeatureClipboard

struct HistoryStoreTests {
    let directory = temporaryDirectory()
    let store: HistoryStore

    init() throws { store = try HistoryStore(directory: directory) }

    private func addText(_ text: String, at seconds: TimeInterval = 0) async throws -> HistoryStore.AddResult {
        try await store.add(ClipContent(kind: .text, text: text), sourceBundleID: "com.apple.Notes", sourceName: "Заметки",
                            date: Date(timeIntervalSince1970: 1_000_000 + seconds))
    }

    @Test func sameContentIsBumpedNotDuplicated() async throws {
        let first = try await addText("один", at: 0)
        _ = try await addText("два", at: 1)
        let again = try await addText("один", at: 2)

        #expect(again == .bumped(again.item))
        #expect(again.item.id == first.item.id)
        #expect(try await store.count() == 2)
        #expect(try await store.items().map(\.text) == ["один", "два"])
    }

    @Test func searchIgnoresCaseInCyrillicAndYo() async throws {
        _ = try await addText("Привет, Ёжик")
        _ = try await addText("hello")
        #expect(try await store.items(query: "ПРИВЕТ").count == 1)
        #expect(try await store.items(query: "ежик").count == 1)
        #expect(try await store.items(query: "заметки").count == 2)  // source app name is searchable
        #expect(try await store.items(query: "%").isEmpty)  // LIKE wildcards are escaped
    }

    @Test func filtersByKindAndKeepsPinnedOnTop() async throws {
        let old = try await addText("старое", at: 0)
        _ = try await store.add(ClipContent(kind: .link, text: "https://a.b"), sourceBundleID: nil, sourceName: nil,
                                date: Date(timeIntervalSince1970: 1_000_010))
        try await store.setPinned(old.item.id, true)

        #expect(try await store.items(kind: .link).count == 1)
        #expect(try await store.items().first?.text == "старое")
        #expect(try await store.items(pinnedOnly: true).count == 1)
    }

    @Test func pruneByCountAndAgeSparesPinned() async throws {
        for i in 0..<10 { _ = try await addText("item \(i)", at: TimeInterval(i)) }
        let pinned = try await store.items().last!  // the oldest
        try await store.setPinned(pinned.id, true)

        let removed = try await store.prune(maxCount: 5, maxAge: nil)
        #expect(removed == 4)  // 9 unpinned → 5 kept
        #expect(try await store.count() == 6)

        let byAge = try await store.prune(maxCount: 100, maxAge: 2, now: Date(timeIntervalSince1970: 1_000_009))
        #expect(byAge == 2)  // items 5…9 remain; 5 and 6 are older than now − 2 s
        #expect(try await store.items().contains { $0.id == pinned.id })
    }

    @Test func imagesAreStoredWithThumbnailAndRemovedOnDelete() async throws {
        let result = try await store.add(ClipContent(kind: .image, image: makePNG(width: 800, height: 600)),
                                         sourceBundleID: nil, sourceName: nil)
        let item = result.item
        let imageURL = try #require(item.imageURL)
        let thumbURL = try #require(item.thumbnailURL)
        #expect(FileManager.default.fileExists(atPath: imageURL.path))
        #expect(FileManager.default.fileExists(atPath: thumbURL.path))
        #expect(item.imageSize == CGSize(width: 800, height: 600))
        #expect(await store.diskUsage() > 0)

        try await store.delete(item.id)
        #expect(!FileManager.default.fileExists(atPath: imageURL.path))
        #expect(!FileManager.default.fileExists(atPath: thumbURL.path))
    }

    @Test func clearCanKeepPinned() async throws {
        let keep = try await addText("keep")
        _ = try await addText("drop")
        try await store.setPinned(keep.item.id, true)

        try await store.clear(keepPinned: true)
        #expect(try await store.items().map(\.text) == ["keep"])
        try await store.clear(keepPinned: false)
        #expect(try await store.count() == 0)
    }

    @Test func historySurvivesReopen() async throws {
        _ = try await addText("persisted")
        let reopened = try HistoryStore(directory: directory)
        #expect(try await reopened.items().first?.text == "persisted")
    }

    @Test func filesAreStoredAsPaths() async throws {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/папка")]
        let result = try await store.add(ClipContent(kind: .files, text: "a.txt\nпапка", fileURLs: urls),
                                         sourceBundleID: nil, sourceName: nil)
        #expect(result.item.fileURLs == urls)
        #expect(try await store.items(query: "папка").count == 1)
    }
}
