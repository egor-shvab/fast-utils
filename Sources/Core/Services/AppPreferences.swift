import Foundation
import Observation

/// Interface language choice. Applied at launch through the app's own
/// `AppleLanguages` default, so a change takes effect after a restart.
public enum InterfaceLanguage: String, CaseIterable, Sendable {
    case system
    case russian = "ru"
    case english = "en"

    static let settingsKey = "app.language"
    static let appleLanguagesKey = "AppleLanguages"

    /// Call before anything is localized (top of `main.swift`).
    public static func applyStored(to defaults: UserDefaults = .standard) {
        let stored = InterfaceLanguage(rawValue: defaults.string(forKey: settingsKey) ?? "") ?? .system
        apply(stored, to: defaults)
    }

    static func apply(_ language: InterfaceLanguage, to defaults: UserDefaults) {
        switch language {
        case .system: defaults.removeObject(forKey: appleLanguagesKey)
        case .russian, .english: defaults.set([language.rawValue], forKey: appleLanguagesKey)
        }
    }
}

/// App-wide preferences from the General tab that are not tied to a single service.
@MainActor
@Observable
public final class AppPreferences {
    @ObservationIgnored private let settings: ScopedSettings

    /// When hidden, Settings open by launching the app again from Finder or Spotlight.
    public var showMenuBarIcon: Bool { didSet { settings.set(showMenuBarIcon, for: "menuBarIcon") } }

    /// Saved choice; the running interface keeps the language it started with.
    public var language: InterfaceLanguage {
        didSet {
            settings.set(language.rawValue, for: "language")
            InterfaceLanguage.apply(language, to: settings.defaults)
        }
    }

    /// The language the interface was started with, to tell whether a restart is needed.
    public let launchLanguage: InterfaceLanguage

    init(settings: ScopedSettings) {
        self.settings = settings
        showMenuBarIcon = settings.value("menuBarIcon", default: true)
        let language = InterfaceLanguage(rawValue: settings.value("language", default: "")) ?? .system
        self.language = language
        launchLanguage = language
    }
}
