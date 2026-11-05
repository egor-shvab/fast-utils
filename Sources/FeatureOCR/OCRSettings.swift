import Core
import Observation

/// OCR preferences, persisted under `ocr.*`.
@MainActor
@Observable
final class OCRSettings {
    /// Short identifiers in priority order ("ru", "en").
    var languages: [String] { didSet { store.set(languages, for: "languages") } }
    var autoDetectLanguage: Bool { didSet { store.set(autoDetectLanguage, for: "autoDetectLanguage") } }
    var lineMode: LineMode { didSet { store.set(lineMode.rawValue, for: "lineMode") } }
    var showResultWindow: Bool { didSet { store.set(showResultWindow, for: "showResultWindow") } }
    var playSound: Bool { didSet { store.set(playSound, for: "playSound") } }

    static let defaultLanguages = ["ru", "en"]

    @ObservationIgnored private let store: ScopedSettings

    init(store: ScopedSettings) {
        self.store = store
        languages = store.value("languages", default: Self.defaultLanguages)
        autoDetectLanguage = store.value("autoDetectLanguage", default: false)
        lineMode = LineMode(rawValue: store.value("lineMode", default: "")) ?? .asOnScreen
        showResultWindow = store.value("showResultWindow", default: false)
        playSound = store.value("playSound", default: false)
    }
}
