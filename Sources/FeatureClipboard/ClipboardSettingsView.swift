import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Not `@State`: see CLAUDE.md (SwiftUI macros without Xcode).
@MainActor
final class ClipboardStatsModel: ObservableObject {
    @Published var count = 0
    @Published var bytes: Int64 = 0

    func load(from store: HistoryStore?) async {
        guard let store else { return }
        count = (try? await store.count()) ?? 0
        bytes = await store.diskUsage()
    }
}

struct ClipboardSettingsView: View {
    @Bindable var settings: ClipboardSettings
    let feature: ClipboardFeature
    @StateObject private var stats = ClipboardStatsModel()

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "clipboard.settings.windowPosition"), selection: $settings.windowPosition) {
                    Text(String(localized: "clipboard.settings.position.mouse")).tag(ClipboardSettings.WindowPosition.mouse)
                    Text(String(localized: "clipboard.settings.position.center")).tag(ClipboardSettings.WindowPosition.center)
                    Text(String(localized: "clipboard.settings.position.textCursor")).tag(ClipboardSettings.WindowPosition.textCursor)
                }
                Toggle(String(localized: "clipboard.settings.autoPaste"), isOn: $settings.autoPaste)
                Toggle(String(localized: "clipboard.settings.restorePrevious"), isOn: $settings.restorePrevious)
                    .disabled(!settings.autoPaste)
                Toggle(String(localized: "clipboard.settings.previewOnSelect"), isOn: $settings.previewOnSelect)
            } header: {
                Text(String(localized: "clipboard.settings.window"))
            } footer: {
                Text(String(localized: "clipboard.settings.windowFooter")).foregroundStyle(.secondary)
            }

            Section {
                Picker(String(localized: "clipboard.settings.maxItems"), selection: $settings.maxItems) {
                    ForEach(ClipboardSettings.maxItemsOptions, id: \.self) { Text("\($0)").tag($0) }
                }
                Picker(String(localized: "clipboard.settings.maxAge"), selection: $settings.maxAgeDays) {
                    ForEach(ClipboardSettings.maxAgeOptions, id: \.self) { days in
                        Text(ageTitle(days)).tag(days)
                    }
                }
                Picker(String(localized: "clipboard.settings.maxImage"), selection: $settings.maxImageMB) {
                    ForEach(ClipboardSettings.maxImageMBOptions, id: \.self) { Text(String(format: String(localized: "clipboard.settings.megabytes"), $0)).tag($0) }
                }
            } header: {
                Text(String(localized: "clipboard.settings.storage"))
            } footer: {
                Text(String(localized: "clipboard.settings.storageFooter")).foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "clipboard.settings.storeText"), isOn: $settings.storeText)
                Toggle(String(localized: "clipboard.settings.storeImages"), isOn: $settings.storeImages)
                Toggle(String(localized: "clipboard.settings.storeFiles"), isOn: $settings.storeFiles)
            } header: {
                Text(String(localized: "clipboard.settings.kinds"))
            }

            Section {
                Toggle(String(localized: "clipboard.settings.ignoreConcealed"), isOn: $settings.ignoreConcealed)
                ForEach(settings.excludedApps, id: \.self) { bundleID in
                    HStack {
                        appIcon(bundleID).resizable().frame(width: 18, height: 18)
                        Text(appName(bundleID))
                        Spacer()
                        Button {
                            settings.excludedApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "clipboard.settings.removeApp"))
                        .help(String(localized: "clipboard.settings.removeApp"))
                    }
                }
                Button(String(localized: "clipboard.settings.addApp"), action: addExcludedApp)
            } header: {
                Text(String(localized: "clipboard.settings.privacy"))
            } footer: {
                Text(String(localized: "clipboard.settings.privacyFooter")).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(String(localized: "clipboard.settings.items"), value: "\(stats.count)")
                LabeledContent(String(localized: "clipboard.settings.diskUsage"),
                               value: ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file))
                Button(String(localized: "clipboard.settings.clear"), role: .destructive, action: clearHistory)
            } header: {
                Text(String(localized: "clipboard.settings.data"))
            }
        }
        .formStyle(.grouped)
        .task { await stats.load(from: feature.store) }
    }

    private func ageTitle(_ days: Int) -> String {
        switch days {
        case 0: String(localized: "clipboard.settings.age.forever")
        case 1: String(localized: "clipboard.settings.age.day")
        case 7: String(localized: "clipboard.settings.age.week")
        case 30: String(localized: "clipboard.settings.age.month")
        default: String(localized: "clipboard.settings.age.3months")
        }
    }

    private func appURL(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private func appName(_ bundleID: String) -> String {
        appURL(bundleID).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }

    private func appIcon(_ bundleID: String) -> Image {
        if let url = appURL(bundleID) { return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)) }
        return Image(systemName: "app.dashed")
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !settings.excludedApps.contains(id) {
                settings.excludedApps.append(id)
            }
        }
    }

    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = String(localized: "clipboard.clear.title")
        alert.informativeText = String(localized: "clipboard.clear.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "clipboard.clear.keepPinned"))
        alert.addButton(withTitle: String(localized: "clipboard.clear.all"))
        alert.addButton(withTitle: String(localized: "clipboard.clear.cancel"))
        let response = alert.runModal()
        guard response != .alertThirdButtonReturn, let store = feature.store else { return }
        let keepPinned = response == .alertFirstButtonReturn
        Task {
            try? await store.clear(keepPinned: keepPinned)
            await stats.load(from: store)
        }
    }
}
