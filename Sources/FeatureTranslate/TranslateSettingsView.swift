import AppKit
import Combine
import Core
import SwiftUI

/// Not `@State` (see CLAUDE.md).
@MainActor
final class LanguageListModel: ObservableObject {
    @Published var languages: [String] = []
    func load() async { languages = await AppleLanguages.supported() }
}

/// API key fields and their check results. Keys live only in the Keychain.
@MainActor
final class APIKeysModel: ObservableObject {
    @Published var deeplKey: String
    @Published var googleKey: String
    @Published var status: [TranslateSettings.EngineKind: String] = [:]
    @Published var checking: TranslateSettings.EngineKind?

    private let secrets: any SecretStore
    private let http: any HTTPClient

    init(secrets: any SecretStore, http: any HTTPClient) {
        self.secrets = secrets
        self.http = http
        deeplKey = secrets.secret(for: TranslateSettings.secretKey(for: .deepl)) ?? ""
        googleKey = secrets.secret(for: TranslateSettings.secretKey(for: .google)) ?? ""
    }

    func save(_ engine: TranslateSettings.EngineKind) {
        let value = (engine == .deepl ? deeplKey : googleKey).trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try secrets.setSecret(value.isEmpty ? nil : value, for: TranslateSettings.secretKey(for: engine))
            status[engine] = nil
        } catch {
            status[engine] = String(localized: "translate.key.saveFailed")
        }
    }

    func check(_ engine: TranslateSettings.EngineKind) {
        save(engine)
        let key = (engine == .deepl ? deeplKey : googleKey).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            status[engine] = OnlineTranslationError.missingKey.message
            return
        }
        checking = engine
        Task {
            defer { checking = nil }
            do {
                if engine == .deepl {
                    let usage = try await DeepLEngine(key: key, http: http).usage()
                    status[engine] = String(format: String(localized: "translate.key.okDeepL"),
                                            usage.used.formatted(), usage.limit.formatted())
                } else {
                    _ = try await GoogleEngine(key: key, http: http)
                        .translate(TranslationRequest(text: "ok", source: "en", target: "ru"))
                    status[engine] = String(localized: "translate.key.ok")
                }
            } catch {
                status[engine] = "⚠️ " + OnlineTranslationError.from(error).message
            }
        }
    }
}

struct TranslateSettingsView: View {
    @Bindable var settings: TranslateSettings
    @StateObject var keys: APIKeysModel
    @StateObject private var list = LanguageListModel()

    init(settings: TranslateSettings, keys: APIKeysModel) {
        self.settings = settings
        _keys = StateObject(wrappedValue: keys)
    }

    var body: some View {
        Form {
            Section {
                languagePicker("translate.settings.primary", selection: $settings.primaryLanguage)
                languagePicker("translate.settings.fallback", selection: $settings.fallbackLanguage)
            } header: {
                Text(String(localized: "translate.settings.languages"))
            } footer: {
                Text(String(localized: "translate.settings.languagesFooter")).foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "translate.settings.autoCopy"), isOn: $settings.autoCopy)
            }

            Section {
                Picker(String(localized: "translate.settings.engine"), selection: $settings.engine) {
                    Text(String(localized: "translate.engine.apple")).tag(TranslateSettings.EngineKind.apple)
                    Text("DeepL").tag(TranslateSettings.EngineKind.deepl)
                    Text("Google Translate").tag(TranslateSettings.EngineKind.google)
                }
                if settings.engine != .apple {
                    keyField(settings.engine)
                    Toggle(String(localized: "translate.settings.fallback.toggle"), isOn: $settings.fallbackToApple)
                }
                Button(String(localized: "translate.settings.manageLanguages")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
                }
            } header: {
                Text(String(localized: "translate.settings.engineSection"))
            } footer: {
                Text(String(localized: settings.engine == .apple ? "translate.settings.engineFooter" : "translate.settings.onlineFooter"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await list.load() }
    }

    @ViewBuilder
    private func keyField(_ engine: TranslateSettings.EngineKind) -> some View {
        let binding = engine == .deepl ? $keys.deeplKey : $keys.googleKey
        LabeledContent(String(localized: engine == .deepl ? "translate.key.deepl" : "translate.key.google")) {
            HStack {
                SecureField("", text: binding, prompt: Text(String(localized: "translate.key.placeholder")))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { keys.save(engine) }
                    .onChange(of: binding.wrappedValue) { keys.save(engine) }
                Button(String(localized: "translate.key.check")) { keys.check(engine) }
                    .disabled(keys.checking != nil)
            }
        }
        if keys.checking == engine {
            ProgressView().controlSize(.small)
        } else if let status = keys.status[engine] {
            Text(status).font(.caption).foregroundStyle(status.hasPrefix("⚠️") ? Color.orange : Color.secondary)
        }
    }

    private func languagePicker(_ title: String.LocalizationValue, selection: Binding<String>) -> some View {
        Picker(String(localized: title), selection: selection) {
            // Keep the current value selectable while the list loads.
            ForEach(list.languages.contains(selection.wrappedValue) ? list.languages : [selection.wrappedValue] + list.languages,
                    id: \.self) { language in
                Text(TranslationDirection.displayName(language)).tag(language)
            }
        }
    }
}
