import Foundation
import Testing
@testable import Core

@MainActor
struct Stage10CoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "FastUtilsTests.\(UUID().uuidString)")!
    }

    @Test func interfaceLanguageSetsAndClearsAppleLanguages() {
        let suite = "FastUtilsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        InterfaceLanguage.apply(.english, to: defaults)
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["en"])
        InterfaceLanguage.apply(.system, to: defaults)
        // Only the app's own override is removed; the system list shows through again.
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
    }

    @Test func storedLanguageIsAppliedAtLaunch() {
        let defaults = makeDefaults()
        defaults.set("ru", forKey: "app.language")
        InterfaceLanguage.applyStored(to: defaults)
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == ["ru"])
    }

    @Test func preferencesPersistAndKeepLaunchLanguage() {
        let store = SettingsStore(defaults: makeDefaults())
        let preferences = AppPreferences(settings: store.app)
        #expect(preferences.showMenuBarIcon)
        #expect(preferences.language == .system)

        preferences.showMenuBarIcon = false
        preferences.language = .english

        let reloaded = AppPreferences(settings: store.app)
        #expect(!reloaded.showMenuBarIcon)
        #expect(reloaded.language == .english)
        #expect(preferences.launchLanguage == .system)
        #expect(store.defaults.array(forKey: "AppleLanguages") as? [String] == ["en"])
    }

    @Test func languageIsExportedWithSettings() throws {
        let store = SettingsStore(defaults: makeDefaults())
        AppPreferences(settings: store.app).language = .russian
        let json = try JSONSerialization.jsonObject(with: store.exportJSON()) as? [String: Any]
        #expect(json?["app.language"] as? String == "ru")
        #expect(json?["AppleLanguages"] == nil)
    }
}
