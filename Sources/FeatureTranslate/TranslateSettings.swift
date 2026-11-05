import Core
import Observation

/// Translation preferences, persisted under `translate.*` (TZ.md §6.2).
@MainActor
@Observable
final class TranslateSettings {
    /// Translate into this language…
    var primaryLanguage: String { didSet { store.set(primaryLanguage, for: "primaryLanguage") } }
    /// …unless the text already is in it.
    var fallbackLanguage: String { didSet { store.set(fallbackLanguage, for: "fallbackLanguage") } }
    var autoCopy: Bool { didSet { store.set(autoCopy, for: "autoCopy") } }

    /// Longer texts ask for confirmation first.
    static let confirmLength = 5_000

    @ObservationIgnored private let store: ScopedSettings

    init(store: ScopedSettings) {
        self.store = store
        primaryLanguage = store.value("primaryLanguage", default: "ru")
        fallbackLanguage = store.value("fallbackLanguage", default: "en")
        autoCopy = store.value("autoCopy", default: false)
    }
}
