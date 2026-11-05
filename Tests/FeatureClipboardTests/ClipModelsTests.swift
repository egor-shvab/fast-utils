import Core
import Foundation
import Testing
@testable import FeatureClipboard

struct ClipModelsTests {
    @Test func filesWin() {
        let snapshot = PasteboardSnapshot(types: ["public.file-url"], string: "a.txt",
                                          fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")])
        #expect(ClipContentFactory.content(from: snapshot)?.kind == .files)
    }

    @Test func imagePreferredByTypeOrder() {
        let snapshot = PasteboardSnapshot(types: ["public.png", "public.utf8-plain-text"], string: "caption", image: makePNG())
        #expect(ClipContentFactory.content(from: snapshot)?.kind == .image)
    }

    @Test func textWithPreviewImageStaysText() {
        let snapshot = PasteboardSnapshot(types: ["public.rtf", "public.utf8-plain-text", "public.tiff"],
                                          string: "Rich text", rtf: Data("r".utf8), image: makePNG())
        let content = ClipContentFactory.content(from: snapshot)
        #expect(content?.kind == .text)
        #expect(content?.rtf == Data("r".utf8))
    }

    @Test func linkOnlyForSingleHTTPURL() {
        #expect(ClipContentFactory.content(from: PasteboardSnapshot(string: " https://example.com/a?b=1 \n"))?.kind == .link)
        #expect(ClipContentFactory.content(from: PasteboardSnapshot(string: "see https://example.com"))?.kind == .text)
        #expect(ClipContentFactory.content(from: PasteboardSnapshot(string: "file:///etc/hosts"))?.kind == .text)
    }

    @Test func whitespaceOnlyIsIgnored() {
        #expect(ClipContentFactory.content(from: PasteboardSnapshot(string: "  \n\t ")) == nil)
        #expect(ClipContentFactory.content(from: PasteboardSnapshot()) == nil)
    }

    @Test func sameContentSameHash() {
        let a = ClipContent(kind: .text, text: "x")
        #expect(a.hash == ClipContent(kind: .text, text: "x", rtf: Data("other formatting".utf8)).hash)
        #expect(a.hash != ClipContent(kind: .text, text: "y").hash)
        #expect(a.hash != ClipContent(kind: .link, text: "x").hash)
    }

    @Test func filterSkipsPasswordsAndExcludedApps() {
        #expect(!ClipboardFilter.allowsReading(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
                                               source: "com.example", excludedApps: [], ignoreConcealed: true))
        #expect(ClipboardFilter.allowsReading(types: ["org.nspasteboard.ConcealedType"],
                                              source: nil, excludedApps: [], ignoreConcealed: false))
        #expect(!ClipboardFilter.allowsReading(types: ["public.utf8-plain-text"], source: "com.apple.keychainaccess",
                                               excludedApps: Set(ClipboardFilter.defaultExcludedApps), ignoreConcealed: true))
        #expect(ClipboardFilter.allowsReading(types: ["public.utf8-plain-text"], source: "com.apple.Notes",
                                              excludedApps: Set(ClipboardFilter.defaultExcludedApps), ignoreConcealed: true))
    }
}
