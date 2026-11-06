import AppKit
import Core
import SwiftUI
import Testing
import Translation
@testable import FeatureTranslate

struct DirectionTests {
    @Test func russianGoesToEnglishOthersToRussian() {
        #expect(TranslationDirection.target(detected: "ru", primary: "ru", fallback: "en") == "en")
        #expect(TranslationDirection.target(detected: "en", primary: "ru", fallback: "en") == "ru")
        #expect(TranslationDirection.target(detected: "de", primary: "ru", fallback: "en") == "ru")
        #expect(TranslationDirection.target(detected: nil, primary: "ru", fallback: "en") == "ru")
    }

    @Test func regionAndScriptVariantsAreTheSameLanguage() {
        #expect(TranslationDirection.sameLanguage("ru-RU", "ru"))
        #expect(TranslationDirection.sameLanguage("zh-Hans", "zh"))
        #expect(!TranslationDirection.sameLanguage("uk", "ru"))
    }

    @Test func detectsCommonLanguages() {
        #expect(LanguageDetector.detect("Привет! Как у тебя дела сегодня?") == "ru")
        #expect(LanguageDetector.detect("The quick brown fox jumps over the lazy dog.") == "en")
        #expect(LanguageDetector.detect("Der schnelle braune Fuchs springt über den faulen Hund.") == "de")
    }

    @Test func tooShortOrAmbiguousIsUnknown() {
        #expect(LanguageDetector.detect("ok") == nil || LanguageDetector.detect("ok") == "en")
        #expect(LanguageDetector.detect("12345 !!!") == nil)
    }

    @Test func displayNamesAreCapitalized() {
        let name = TranslationDirection.displayName("en")
        #expect(name.first?.isUppercase == true)
    }
}

@MainActor
final class FakeEngine: TranslationEngine {
    var name: String { "Fake" }
    var hostView: AnyView? { nil }
    var requests: [TranslationRequest] = []
    var failure: Error?
    var prepared = false

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        requests.append(request)
        if let failure { throw failure }
        return TranslationResult(text: "[\(request.target)] \(request.text)", source: request.source ?? "en", target: request.target)
    }

    func prepare(source: String?, target: String) async throws { prepared = true; failure = nil }
}

@MainActor
struct TranslationViewModelTests {
    let context = AppContext.testing()
    let engine = FakeEngine()
    var settings: TranslateSettings { TranslateSettings(store: context.settings.scoped("translate")) }

    private func waitIdle(_ model: TranslationViewModel) async {
        for _ in 0..<100 where model.isLoading || (model.translation == nil && model.error == nil) {
            await Task.yield()
        }
    }

    @Test func englishTextIsTranslatedIntoRussian() async {
        let model = TranslationViewModel(text: "Good morning, how are you doing today?", engine: engine, settings: settings)
        #expect(model.source == "en")
        #expect(model.target == "ru")
        model.start()
        await waitIdle(model)
        #expect(model.translation == "[ru] Good morning, how are you doing today?")
        #expect(engine.requests.first?.source == "en")
    }

    @Test func russianTextGoesToFallback() async {
        let model = TranslationViewModel(text: "Доброе утро, как у тебя сегодня дела?", engine: engine, settings: settings)
        #expect(model.target == "en")
    }

    @Test func swapSwitchesPrimaryAndFallbackWithAutoSource() async {
        let model = TranslationViewModel(text: "Good morning, how are you doing today?", engine: engine, settings: settings)
        model.swapDirection()
        await waitIdle(model)
        #expect(model.target == "en")
        #expect(engine.requests.last?.source == nil)
    }

    @Test func choosingTargetRetranslates() async {
        let model = TranslationViewModel(text: "Good morning, how are you doing today?", engine: engine, settings: settings)
        model.setTarget("de")
        await waitIdle(model)
        #expect(engine.requests.last?.target == "de")
        #expect(model.translation?.hasPrefix("[de]") == true)
    }

    @Test func errorsAreReadable() async {
        engine.failure = TranslationError.unsupportedLanguagePairing
        let model = TranslationViewModel(text: "Good morning, how are you doing today?", engine: engine, settings: settings)
        model.start()
        await waitIdle(model)
        #expect(model.error == String(localized: "translate.error.unsupported"))
        #expect(model.translation == nil)
    }

    @Test func callbackGetsTranslation() async {
        let model = TranslationViewModel(text: "Good morning, how are you doing today?", engine: engine, settings: settings)
        var received: String?
        model.onTranslated = { received = $0 }
        model.start()
        await waitIdle(model)
        #expect(received == model.translation)
    }
}

@MainActor
struct TranslateFeatureTests {
    let board = NSPasteboard(name: NSPasteboard.Name("FastUtilsTests.\(UUID().uuidString)"))
    let context: AppContext
    let registry: FeatureRegistry

    init() {
        context = AppContext.testing(pasteboard: board)
        registry = FeatureRegistry(context: context, types: [TranslateFeature.self])
    }

    @Test func internalActionIsRegisteredButHidden() async {
        await registry.startEnabledFeatures()
        #expect(context.actions.contains("translate.show"))
        let feature = registry.feature("translate")!
        #expect(feature.menuItems.map(\.actionID) == ["translate.clipboard"])
        #expect(context.hotkeys.shortcut(for: "translate.clipboard")?.description == "⌥⌘T")
    }

    @Test func emptyClipboardOpensNoWindow() async {
        await registry.startEnabledFeatures()
        board.clearContents()
        try? await context.actions.perform("translate.clipboard")
        #expect(!context.panels.isPresented(TranslateFeature.panelID))
    }

    @Test func passwordOnClipboardIsNotTranslated() async {
        await registry.startEnabledFeatures()
        let feature = registry.feature("translate") as! TranslateFeature
        feature.settings.autoCopy = true
        let item = NSPasteboardItem()
        item.setString("hunter2", forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        board.clearContents()
        board.writeObjects([item])

        try? await context.actions.perform("translate.clipboard")

        #expect(!context.panels.isPresented(TranslateFeature.panelID))
        #expect(feature.cache.count == 0)
        // The clipboard is untouched: still the password item, not a "translation" of it.
        #expect(board.pasteboardItems?.first?.types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true)
    }

    @Test func plainTextOnClipboardOpensWindow() async {
        await registry.startEnabledFeatures()
        board.clearContents()
        board.setString("Hello, world", forType: .string)
        try? await context.actions.perform("translate.clipboard")
        #expect(context.panels.isPresented(TranslateFeature.panelID))
        context.panels.close(TranslateFeature.panelID)
    }

    @Test func appleSupportsRussianAndEnglish() async {
        let languages = await AppleLanguages.supported()
        #expect(languages.contains("ru"))
        #expect(languages.contains("en"))
    }
}
