import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let registry: FeatureRegistry
    let context: AppContext
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            GeneralSettingsView(registry: registry, launchAtLogin: context.launchAtLogin, hud: context.hud,
                                settings: context.settings, preferences: context.preferences)
                .tabItem { Label(String(localized: "settings.tab.general"), systemImage: "gearshape") }
                .tag(SettingsTab.general)

            ShortcutsSettingsView(registry: registry, hotkeys: context.hotkeys)
                .tabItem { Label(String(localized: "settings.tab.shortcuts"), systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            ForEach(featureTabs, id: \.id) { tab in
                tab.view
                    .tabItem { Label(tab.title, systemImage: tab.icon) }
                    .tag(SettingsTab.feature(tab.id))
            }

            PermissionsSettingsView(registry: registry, service: context.permissions)
                .tabItem { Label(String(localized: "settings.tab.permissions"), systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)

            AboutView(storage: context.storage)
                .tabItem { Label(String(localized: "settings.tab.about"), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 620, height: 480)
    }

    /// Tabs of enabled features that provide a settings view.
    private var featureTabs: [FeatureTab] {
        registry.features.compactMap { feature in
            let id = FeatureRegistry.id(of: feature)
            guard registry.isEnabled(id), let view = feature.settingsView else { return nil }
            return FeatureTab(id: id, title: feature.title, icon: feature.icon, view: view)
        }
    }

    private struct FeatureTab {
        let id: FeatureID
        let title: String
        let icon: String
        let view: AnyView
    }
}

struct GeneralSettingsView: View {
    let registry: FeatureRegistry
    let launchAtLogin: LaunchAtLogin
    @Bindable var hud: HUDService
    let settings: SettingsStore
    @Bindable var preferences: AppPreferences

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "settings.general.launchAtLogin"), isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                Picker(String(localized: "settings.general.language"), selection: Binding(
                    get: { preferences.language },
                    set: { changeLanguage($0) }
                )) {
                    Text(String(localized: "settings.general.language.system")).tag(InterfaceLanguage.system)
                    // Language names are shown in their own language, as macOS does.
                    Text(verbatim: "Русский").tag(InterfaceLanguage.russian)
                    Text(verbatim: "English").tag(InterfaceLanguage.english)
                }
                Toggle(String(localized: "settings.general.menuBarIcon"), isOn: $preferences.showMenuBarIcon)
            } footer: {
                if !preferences.showMenuBarIcon {
                    Text(String(localized: "settings.general.menuBarIconFooter")).foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle(String(localized: "settings.general.hud"), isOn: $hud.isEnabled)
                Picker(String(localized: "settings.general.hudPosition"), selection: $hud.position) {
                    Text(String(localized: "settings.general.hudPosition.bottomCenter")).tag(HUDService.Position.bottomCenter)
                    Text(String(localized: "settings.general.hudPosition.nearCursor")).tag(HUDService.Position.nearCursor)
                }
                .disabled(!hud.isEnabled)
                Button(String(localized: "settings.general.hudTest")) {
                    hud.show(String(localized: "settings.general.hudTestMessage"))
                }
                .disabled(!hud.isEnabled)
            } header: {
                Text(String(localized: "settings.general.notifications"))
            }
            Section {
                ForEach(registry.features.map { FeatureRegistry.id(of: $0) }, id: \.self) { id in
                    let feature = registry.feature(id)!
                    Toggle(isOn: Binding(
                        get: { registry.isEnabled(id) },
                        set: { newValue in Task { await registry.setEnabled(newValue, for: id) } }
                    )) {
                        Label(feature.title, systemImage: feature.icon)
                    }
                }
            } header: {
                Text(String(localized: "settings.general.features"))
            } footer: {
                Text(String(localized: "settings.general.featuresFooter"))
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button(String(localized: "settings.general.export"), action: exportSettings)
                    Button(String(localized: "settings.general.import"), action: importSettings)
                }
            } header: {
                Text(String(localized: "settings.general.backup"))
            } footer: {
                Text(String(localized: "settings.general.backupFooter")).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FastUtils Settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.exportJSON().write(to: url)
        } catch {
            showError(error)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.importJSON(Data(contentsOf: url))
        } catch {
            showError(error)
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "settings.general.imported")
        alert.informativeText = String(localized: "settings.general.importedRestart")
        alert.addButton(withTitle: String(localized: "settings.general.restart"))
        alert.addButton(withTitle: String(localized: "settings.general.later"))
        if alert.runModal() == .alertFirstButtonReturn { AppRelauncher.relaunch() }
    }

    private func changeLanguage(_ language: InterfaceLanguage) {
        guard language != preferences.language else { return }
        preferences.language = language
        guard language != preferences.launchLanguage else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "settings.general.languageChanged")
        alert.informativeText = String(localized: "settings.general.languageRestart")
        alert.addButton(withTitle: String(localized: "settings.general.restart"))
        alert.addButton(withTitle: String(localized: "settings.general.later"))
        if alert.runModal() == .alertFirstButtonReturn { AppRelauncher.relaunch() }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

/// Restarts the app (features read settings at launch).
@MainActor
enum AppRelauncher {
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.7; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}

struct AboutView: View {
    let storage: StorageService

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(AppInfo.name).font(.title.bold())
            Text(String(format: String(localized: "settings.about.version"), AppInfo.version))
                .foregroundStyle(.secondary)
            Button(String(localized: "settings.about.openData")) {
                try? FileManager.default.createDirectory(at: storage.baseURL, withIntermediateDirectories: true)
                NSWorkspace.shared.open(storage.baseURL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
