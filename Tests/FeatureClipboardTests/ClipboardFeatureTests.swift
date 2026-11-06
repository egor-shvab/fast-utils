import AppKit
import Core
import Testing
@testable import FeatureClipboard

@MainActor
struct ClipboardFeatureTests {
    let board = NSPasteboard(name: NSPasteboard.Name("FastUtilsTests.\(UUID().uuidString)"))
    let context: AppContext
    let registry: FeatureRegistry
    var feature: ClipboardFeature { registry.feature("clipboard") as! ClipboardFeature }

    init() {
        context = AppContext.testing(pasteboard: board)
        registry = FeatureRegistry(context: context, types: [ClipboardFeature.self])
    }

    private func copy(_ text: String, concealed: Bool = false) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if concealed { item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) }
        board.clearContents()
        board.writeObjects([item])
        context.pasteboard.checkForChanges()
    }

    private func waitForCount(_ expected: Int) async throws -> Int {
        var count = 0
        for _ in 0..<100 {
            count = try await feature.store?.count() ?? 0
            if count == expected { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        return count
    }

    @Test func copiedTextLandsInHistory() async throws {
        await registry.startEnabledFeatures()
        copy("первая")
        copy("вторая")
        #expect(try await waitForCount(2) == 2)
    }

    @Test func passwordsAreNotStored() async throws {
        await registry.startEnabledFeatures()
        copy("hunter2", concealed: true)
        copy("обычный текст")
        #expect(try await waitForCount(1) == 1)
        #expect(try await feature.store?.items().first?.text == "обычный текст")
    }

    @Test func pausedHistoryRecordsNothing() async throws {
        await registry.startEnabledFeatures()
        feature.setPause(.until(Date().addingTimeInterval(60)))
        #expect(context.statusIndicator.symbol != nil)
        copy("на паузе")
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await feature.store?.count() == 0)

        feature.resume()
        #expect(context.statusIndicator.symbol == nil)
        copy("после паузы")
        #expect(try await waitForCount(1) == 1)
    }

    @Test func indefinitePauseSurvivesRestart() async throws {
        await registry.startEnabledFeatures()
        feature.setPause(.indefinitely)
        let restarted = ClipboardFeature(context: context)
        #expect(restarted.pause == .indefinitely)
        restarted.resume()
    }

    @Test func technicalWritesAreIgnored() async throws {
        await registry.startEnabledFeatures()
        context.pasteboard.writeText("служебная запись", recordInHistory: false)
        context.pasteboard.checkForChanges()
        copy("пользователь")
        #expect(try await waitForCount(1) == 1)
        #expect(try await feature.store?.items().first?.text == "пользователь")
    }

    @Test func disabledKindIsSkipped() async throws {
        await registry.startEnabledFeatures()
        feature.settings.storeText = false
        copy("text")
        try await Task.sleep(for: .milliseconds(100))
        #expect(try await feature.store?.count() == 0)
    }

    @Test func privacySettingsReachCoreAndAreResetOnStop() async {
        await registry.startEnabledFeatures()
        #expect(context.pasteboard.excludedApps.contains("com.apple.keychainaccess"))
        #expect(!context.pasteboard.monitorReadsConcealed)

        feature.settings.excludedApps.append("com.example.vault")
        feature.settings.ignoreConcealed = false
        #expect(context.pasteboard.excludedApps.contains("com.example.vault"))
        #expect(context.pasteboard.monitorReadsConcealed)

        await registry.setEnabled(false, for: "clipboard")
        #expect(context.pasteboard.excludedApps.isEmpty)
        #expect(!context.pasteboard.monitorReadsConcealed)
    }

    @Test func copiesMarkedWithExcludedSourceAreSkipped() async throws {
        await registry.startEnabledFeatures()
        feature.settings.excludedApps = ["com.example.vault"]
        let item = NSPasteboardItem()
        item.setString("из хранилища", forType: .string)
        item.setString("com.example.vault", forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
        board.clearContents()
        board.writeObjects([item])
        context.pasteboard.checkForChanges()
        copy("обычный текст")
        #expect(try await waitForCount(1) == 1)
        #expect(try await feature.store?.items().first?.text == "обычный текст")
    }

    @Test func hugeTextIsNotStored() async throws {
        await registry.startEnabledFeatures()
        copy(String(repeating: "a", count: ClipContent.maxTextBytes + 1))
        copy("обычный текст")
        #expect(try await waitForCount(1) == 1)
        #expect(try await feature.store?.items().first?.text == "обычный текст")
    }

    @Test func imageIsNeitherReadNorStoredAsTextWhenImagesAreOff() async throws {
        await registry.startEnabledFeatures()
        feature.settings.storeImages = false
        #expect(!context.pasteboard.monitorReadsImages)

        // A browser's "Copy Image": the picture first, its alt text next to it.
        let item = NSPasteboardItem()
        item.setData(makePNG(), forType: .png)
        item.setString("подпись картинки", forType: .string)
        board.clearContents()
        board.writeObjects([item])
        context.pasteboard.checkForChanges()
        copy("обычный текст")
        #expect(try await waitForCount(1) == 1)
        #expect(try await feature.store?.items().first?.text == "обычный текст")

        await registry.setEnabled(false, for: "clipboard")
        #expect(context.pasteboard.monitorReadsImages)
    }

    @Test func pauseMenuReflectsState() async {
        await registry.startEnabledFeatures()
        #expect(feature.menuItems.contains { !$0.submenu.isEmpty })
        feature.setPause(.untilRestart)
        #expect(!feature.menuItems.contains { !$0.submenu.isEmpty })
        #expect(feature.menuItems.contains { $0.handler != nil })
        feature.resume()
    }
}
