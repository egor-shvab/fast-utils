import AppKit
import Carbon.HIToolbox
import Core
import OSLog
import SwiftUI

/// Function 2 (TZ.md §6): translate the clipboard text and show it in a floating window.
public final class TranslateFeature: Feature {
    public static let id: FeatureID = "translate"
    static let panelID = "translate.window"

    private let context: AppContext
    private let log: Logger
    let settings: TranslateSettings
    let cache = TranslationCache()
    /// Network access; replaced in tests.
    var http: any HTTPClient = URLSessionHTTPClient()

    public init(context: AppContext) {
        self.context = context
        log = context.logger(Self.id.rawValue)
        settings = TranslateSettings(store: context.settings.scoped(Self.id))
    }

    public var title: String { String(localized: "feature.translate.title") }
    public var icon: String { "character.bubble" }
    public var summary: String { String(localized: "feature.translate.summary") }
    public var tint: Color { .purple }
    public var requiredPermissions: Set<Permission> { [.pasteboard] }

    public var actions: [FeatureAction] {
        [
            FeatureAction(
                id: "translate.clipboard",
                title: String(localized: "translate.action.clipboard"),
                defaultShortcut: Shortcut(kVK_ANSI_T, [.option, .command])
            ) { [weak self] _ in
                await self?.translateClipboard()
                return .none
            },
            // For chains ("recognize and translate") and the history menu: input `.text`.
            FeatureAction(
                id: "translate.show", title: String(localized: "translate.action.show"), isInternal: true,
                accepts: [.text], contentTitle: String(localized: "translate.action.translate")
            ) { [weak self] input in
                guard case .text(let text) = input else { return .none }
                self?.show(text)
                return .none
            },
        ]
    }

    public var settingsView: AnyView? {
        AnyView(TranslateSettingsView(settings: settings, keys: APIKeysModel(secrets: context.secrets, http: http)))
    }

    // MARK: Actions

    /// ⌥⌘T: the selection (if enabled and present), else clipboard text, else text on a
    /// clipboard image (via the OCR feature's action).
    func translateClipboard() async {
        // Pressing the shortcut again closes the window.
        if context.panels.isPresented(Self.panelID) {
            context.panels.close(Self.panelID)
            return
        }
        if settings.translateSelection, let selected = await context.paste.copySelection() {
            show(selected)
            return
        }
        if let text = context.pasteboard.readText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            show(text)
            return
        }
        if let image = context.pasteboard.readImage() {
            await translateImage(image)
            return
        }
        context.hud.show(String(localized: "translate.hud.noText"), icon: "character.bubble", style: .info)
    }

    private func translateImage(_ image: CGImage) async {
        do {
            let output = try await context.actions.perform("ocr.recognizeImage", input: .image(image))
            guard case .text(let text) = output, !text.isEmpty else {
                context.hud.show(String(localized: "translate.hud.noTextOnImage"), icon: "photo", style: .info)
                return
            }
            show(text)
        } catch ActionError.notFound {
            context.hud.show(String(localized: "translate.hud.enableOCR"), icon: "photo", style: .info)
        } catch {
            context.hud.show(String(localized: "translate.hud.noTextOnImage"), icon: "photo", style: .info)
        }
    }

    func show(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, confirmLength(text.count) else { return }

        let engine = makeEngine()
        let model = TranslationViewModel(text: text, engine: engine, settings: settings)
        // Length and languages only — never the text.
        log.notice("Translate \(text.count) chars, \(model.source ?? "auto", privacy: .public) → \(model.target, privacy: .public)")
        model.onTranslated = { [weak self] translation in
            guard let self, settings.autoCopy else { return }
            context.pasteboard.writeText(translation)
        }
        model.start()  // before showing, so the first frame already holds the panel open
        context.panels.present(id: Self.panelID, size: CGSize(width: 460, height: 300)) { handle in
            TranslationView(model: model, handle: handle) { [weak self] translation in
                self?.context.pasteboard.writeText(translation)
                self?.context.hud.show(String(localized: "translate.hud.copied"))
                handle.close()
            }
        }
    }

    /// The engine chosen in settings, wrapped with the cache and the Apple fallback.
    func makeEngine() -> ResilientEngine {
        let apple = AppleTranslationEngine()
        var primary: (any TranslationEngine)?
        var primaryError: OnlineTranslationError?
        if settings.engine != .apple {
            let key = context.secrets.secret(for: TranslateSettings.secretKey(for: settings.engine))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if key.isEmpty {
                primaryError = .missingKey
            } else {
                primary = settings.engine == .deepl ? DeepLEngine(key: key, http: http) : GoogleEngine(key: key, http: http)
            }
        }
        return ResilientEngine(
            primary: primary, primaryError: primaryError, apple: apple,
            fallbackToApple: settings.fallbackToApple, cache: cache, cacheKey: settings.engine.rawValue
        )
    }

    private func confirmLength(_ length: Int) -> Bool {
        guard length > TranslateSettings.confirmLength else { return true }
        let alert = NSAlert()
        alert.messageText = String(format: String(localized: "translate.confirm.title"), length)
        alert.informativeText = String(localized: "translate.confirm.message")
        alert.addButton(withTitle: String(localized: "translate.confirm.translate"))
        alert.addButton(withTitle: String(localized: "translate.confirm.cancel"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
