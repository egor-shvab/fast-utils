import Combine
import Core
import Foundation
import Translation

/// State of one translation window. Not `@State` (see CLAUDE.md).
@MainActor
final class TranslationViewModel: ObservableObject {
    let original: String
    @Published private(set) var translation: String?
    @Published private(set) var source: String?
    @Published private(set) var target: String
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    /// Offer to download language data (Apple reported it is missing).
    @Published private(set) var canDownload = false
    @Published var showsOriginal = false
    @Published private(set) var targets: [String] = []

    let engine: any TranslationEngine
    private let settings: TranslateSettings
    var onTranslated: ((String) -> Void)?
    private var task: Task<Void, Never>?

    init(text: String, engine: any TranslationEngine, settings: TranslateSettings) {
        original = text
        self.engine = engine
        self.settings = settings
        let detected = LanguageDetector.detect(text)
        source = detected
        target = TranslationDirection.target(
            detected: detected, primary: settings.primaryLanguage, fallback: settings.fallbackLanguage
        )
    }

    var directionTitle: String {
        let from = source.map(TranslationDirection.displayName) ?? String(localized: "translate.window.autoDetect")
        return "\(from) → \(TranslationDirection.displayName(target))"
    }

    func start() {
        translate()
        Task { targets = await AppleLanguages.supported() }
    }

    func setTarget(_ language: String) {
        guard language != target else { return }
        target = language
        translate()
    }

    /// ⇄ — switch between the primary and the fallback language (e.g. when detection was wrong).
    func swapDirection() {
        let next = TranslationDirection.sameLanguage(target, settings.primaryLanguage)
            ? settings.fallbackLanguage : settings.primaryLanguage
        // The text is presumably in the language we were translating into.
        source = nil
        target = next
        translate()
    }

    func downloadAndRetry() {
        task?.cancel()
        task = Task {
            canDownload = false
            isLoading = true
            do {
                try await engine.prepare(source: source, target: target)
            } catch {
                show(error)
                isLoading = false
                return
            }
            await runTranslation()
        }
    }

    private func translate() {
        task?.cancel()
        isLoading = true  // synchronously: the window holds itself open from the first frame
        task = Task { await runTranslation() }
    }

    private func runTranslation() async {
        isLoading = true
        error = nil
        canDownload = false
        defer { isLoading = false }
        let request = TranslationRequest(
            text: original,
            source: source.flatMap { TranslationDirection.sameLanguage($0, target) ? nil : $0 },
            target: target
        )
        do {
            let result = try await engine.translate(request)
            guard !Task.isCancelled else { return }
            translation = result.text
            if let detected = result.source { source = detected }
            onTranslated?(result.text)
        } catch is CancellationError {
            return
        } catch {
            show(error)
        }
    }

    private func show(_ error: Error) {
        // macOS 26+ reports missing language data; on macOS 15 the system offers the download itself.
        if #available(macOS 26, *), TranslationError.notInstalled ~= error {
            self.error = String(localized: "translate.error.notInstalled")
            canDownload = true
            return
        }
        switch error {
        case TranslationError.unsupportedLanguagePairing, TranslationError.unsupportedSourceLanguage,
             TranslationError.unsupportedTargetLanguage:
            self.error = String(localized: "translate.error.unsupported")
        case TranslationError.unableToIdentifyLanguage:
            self.error = String(localized: "translate.error.unknownLanguage")
        case TranslationError.nothingToTranslate:
            self.error = String(localized: "translate.error.empty")
        default:
            self.error = String(localized: "translate.error.generic")
        }
    }
}
