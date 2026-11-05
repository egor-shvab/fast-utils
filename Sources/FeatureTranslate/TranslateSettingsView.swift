import AppKit
import Combine
import SwiftUI

/// Not `@State` (see CLAUDE.md).
@MainActor
final class LanguageListModel: ObservableObject {
    @Published var languages: [String] = []
    func load() async { languages = await AppleLanguages.supported() }
}

struct TranslateSettingsView: View {
    @Bindable var settings: TranslateSettings
    @StateObject private var list = LanguageListModel()

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
                LabeledContent(String(localized: "translate.settings.engine"), value: String(localized: "translate.engine.apple"))
                Button(String(localized: "translate.settings.manageLanguages")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
                }
            } footer: {
                Text(String(localized: "translate.settings.engineFooter")).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await list.load() }
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
