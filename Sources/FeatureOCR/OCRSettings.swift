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
    var codeMode: CodeMode { didSet { store.set(codeMode.rawValue, for: "codeMode") } }
    /// "Recognize and translate" also copies the recognized text.
    var copyWhenTranslating: Bool { didSet { store.set(copyWhenTranslating, for: "copyWhenTranslating") } }
    var showMagnifier: Bool { didSet { store.set(showMagnifier, for: "showMagnifier") } }

    /// QR codes and barcodes in the selected area.
    enum CodeMode: String, CaseIterable, Sendable {
        case off
        /// Code contents first, then the recognized text.
        case withText
        /// Only the code contents when a code is found; otherwise the text.
        case codeOnly
    }

    static let defaultLanguages = ["ru", "en"]

    @ObservationIgnored private let store: ScopedSettings

    init(store: ScopedSettings) {
        self.store = store
        languages = store.value("languages", default: Self.defaultLanguages)
        autoDetectLanguage = store.value("autoDetectLanguage", default: false)
        lineMode = LineMode(rawValue: store.value("lineMode", default: "")) ?? .asOnScreen
        showResultWindow = store.value("showResultWindow", default: false)
        playSound = store.value("playSound", default: false)
        codeMode = CodeMode(rawValue: store.value("codeMode", default: "")) ?? .withText
        copyWhenTranslating = store.value("copyWhenTranslating", default: true)
        showMagnifier = store.value("showMagnifier", default: true)
    }
}
