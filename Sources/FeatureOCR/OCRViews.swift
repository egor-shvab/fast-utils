import Combine
import Core
import SwiftUI

struct OCRSettingsView: View {
    @Bindable var settings: OCRSettings
    private let supported = TextRecognizer.supportedLanguages()

    var body: some View {
        Group {
            Section {
                Toggle(String(localized: "ocr.settings.autoDetect"), isOn: $settings.autoDetectLanguage)
                ForEach(supported, id: \.self) { code in
                    Toggle(isOn: binding(for: code)) {
                        HStack {
                            Text(Locale.current.localizedString(forIdentifier: code)?.capitalized ?? code)
                            if let index = settings.languages.firstIndex(of: code) {
                                Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(settings.languages == [code])
                }
            } header: {
                Text(String(localized: "ocr.settings.languages"))
            } footer: {
                Text(String(localized: "ocr.settings.languagesFooter")).foregroundStyle(.secondary)
            }

            Section {
                Picker(String(localized: "ocr.settings.lineMode"), selection: $settings.lineMode) {
                    Text(String(localized: "ocr.settings.lineMode.asOnScreen")).tag(LineMode.asOnScreen)
                    Text(String(localized: "ocr.settings.lineMode.joinParagraphs")).tag(LineMode.joinParagraphs)
                }
                Picker(String(localized: "ocr.settings.codes"), selection: $settings.codeMode) {
                    Text(String(localized: "ocr.settings.codes.off")).tag(OCRSettings.CodeMode.off)
                    Text(String(localized: "ocr.settings.codes.withText")).tag(OCRSettings.CodeMode.withText)
                    Text(String(localized: "ocr.settings.codes.codeOnly")).tag(OCRSettings.CodeMode.codeOnly)
                }
                Toggle(String(localized: "ocr.settings.showResultWindow"), isOn: $settings.showResultWindow)
                Toggle(String(localized: "ocr.settings.copyWhenTranslating"), isOn: $settings.copyWhenTranslating)
                Toggle(String(localized: "ocr.settings.showMagnifier"), isOn: $settings.showMagnifier)
                Toggle(String(localized: "ocr.settings.playSound"), isOn: $settings.playSound)
            } header: {
                Text(String(localized: "ocr.settings.result"))
            }
        }
    }

    /// Checked languages keep their priority order; at least one stays checked.
    private func binding(for code: String) -> Binding<Bool> {
        Binding(
            get: { settings.languages.contains(code) },
            set: { isOn in
                if isOn, !settings.languages.contains(code) {
                    settings.languages.append(code)
                } else if !isOn, settings.languages.count > 1 {
                    settings.languages.removeAll { $0 == code }
                }
            }
        )
    }
}

/// Not `@State`: see CLAUDE.md (SwiftUI macros without Xcode).
@MainActor
final class OCRResultModel: ObservableObject {
    @Published var text: String
    init(text: String) { self.text = text }
}

/// Optional result window (TZ.md §5.4): edit the recognized text, then copy it.
struct OCRResultView: View {
    @ObservedObject var model: OCRResultModel
    @Bindable var handle: PanelHandle
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "ocr.result.title")).font(.headline)
                Spacer()
                Toggle(isOn: $handle.isPinned) { Image(systemName: handle.isPinned ? "pin.fill" : "pin") }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .help(String(localized: "panel.pin"))
                    .accessibilityLabel(String(localized: "panel.pin"))
            }
            TextEditor(text: $model.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Text(String(localized: "panel.hint")).font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button(String(localized: "ocr.result.copy")) { onCopy(model.text) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .padding(.top, 8)
    }
}
