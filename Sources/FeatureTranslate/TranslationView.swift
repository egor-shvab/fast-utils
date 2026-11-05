import Core
import SwiftUI

/// The floating translation window (TZ.md §6.4).
struct TranslationView: View {
    @ObservedObject var model: TranslationViewModel
    @Bindable var handle: PanelHandle
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    content
                    DisclosureGroup(String(localized: "translate.window.original"), isExpanded: $model.showsOriginal) {
                        Text(model.original)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    .font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(16)
        .padding(.top, 8)
        .background(model.engine.hostView)
        // Apple may show its language download prompt during a translation; the panel must not
        // close when that prompt takes focus.
        .onAppear { handle.holdsOpen = model.isLoading }
        .onChange(of: model.isLoading) { _, loading in handle.holdsOpen = loading }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(model.targets, id: \.self) { language in
                    Button(TranslationDirection.displayName(language)) { model.setTarget(language) }
                }
            } label: {
                Text(model.directionTitle).font(.headline)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "translate.window.chooseTarget"))

            Button { model.swapDirection() } label: { Image(systemName: "arrow.left.arrow.right") }
                .buttonStyle(.borderless)
                .help(String(localized: "translate.window.swap"))

            Spacer()
            Toggle(isOn: $handle.isPinned) { Image(systemName: handle.isPinned ? "pin.fill" : "pin") }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help(String(localized: "panel.pin"))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.error {
            VStack(alignment: .leading, spacing: 8) {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                if model.canDownload {
                    Button(String(localized: "translate.window.download")) { model.downloadAndRetry() }
                }
            }
        } else if model.isLoading && model.translation == nil {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "translate.window.translating")).foregroundStyle(.secondary)
            }
        } else if let translation = model.translation {
            Text(translation)
                .font(.title3)
                .textSelection(.enabled)
                .opacity(model.isLoading ? 0.5 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Text(model.engine.name).font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button(String(localized: "translate.window.copy")) {
                if let translation = model.translation { onCopy(translation) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.translation == nil)
        }
    }
}
