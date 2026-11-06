import Core
import Observation

/// Translation preferences, persisted under `translate.*`.
@MainActor
@Observable
final class TranslateSettings {
    /// Translate into this language…
    var primaryLanguage: String { didSet { store.set(primaryLanguage, for: "primaryLanguage") } }
    /// …unless the text already is in it.
    var fallbackLanguage: String { didSet { store.set(fallbackLanguage, for: "fallbackLanguage") } }
    var autoCopy: Bool { didSet { store.set(autoCopy, for: "autoCopy") } }
    /// Translate the selected text when there is one (copies it with ⌘C, then restores the clipboard).
    var translateSelection: Bool { didSet { store.set(translateSelection, for: "translateSelection") } }
    var engine: EngineKind { didSet { store.set(engine.rawValue, for: "engine") } }
    /// Use Apple when the online engine fails (no network, bad key, quota).
    var fallbackToApple: Bool { didSet { store.set(fallbackToApple, for: "fallbackToApple") } }

    enum EngineKind: String, CaseIterable, Sendable { case apple, deepl, google }

    /// Keychain accounts of the API keys (never in UserDefaults).
    static func secretKey(for engine: EngineKind) -> String { "translate.\(engine.rawValue).apiKey" }

    /// Longer texts ask for confirmation first.
    static let confirmLength = 5_000

    @ObservationIgnored private let store: ScopedSettings

    init(store: ScopedSettings) {
        self.store = store
        primaryLanguage = store.value("primaryLanguage", default: "ru")
        fallbackLanguage = store.value("fallbackLanguage", default: "en")
        autoCopy = store.value("autoCopy", default: false)
        translateSelection = store.value("translateSelection", default: false)
        engine = EngineKind(rawValue: store.value("engine", default: "")) ?? .apple
        fallbackToApple = store.value("fallbackToApple", default: true)
    }
}
