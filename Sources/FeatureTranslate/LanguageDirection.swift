import Foundation
import NaturalLanguage

/// Detects the language of a text (NaturalLanguage, on device).
enum LanguageDetector {
    /// Short identifier ("ru", "en", "zh-Hans") or `nil` when unsure (very short or mixed text).
    static func detect(_ text: String, minimumConfidence: Double = 0.6) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2_000)))
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= minimumConfidence, language != .undetermined
        else { return nil }
        return language.rawValue
    }
}

/// Translate into the primary language, unless the text already is in it — then
/// into the fallback one.
enum TranslationDirection {
    static func target(detected: String?, primary: String, fallback: String) -> String {
        guard let detected, sameLanguage(detected, primary) else { return primary }
        return fallback
    }

    /// "ru" == "ru-RU", "zh-Hans" == "zh".
    static func sameLanguage(_ a: String, _ b: String) -> Bool {
        baseCode(a) == baseCode(b)
    }

    static func baseCode(_ identifier: String) -> String {
        Locale.Language(identifier: identifier).languageCode?.identifier ?? identifier
    }

    /// "Русский", "Английский" in the interface language.
    static func displayName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier).map { $0.prefix(1).uppercased() + $0.dropFirst() }
            ?? identifier
    }
}
