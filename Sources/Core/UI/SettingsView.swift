import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let registry: FeatureRegistry
    let context: AppContext
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: Binding<SettingsTab?>(
                get: { navigation.selectedTab },
                set: { if let tab = $0 { navigation.selectedTab = tab } }
            )) {
                SidebarRow(title: String(localized: "settings.tab.general"), icon: "gearshape", tint: .gray)
                    .tag(SettingsTab.general)

                Section(String(localized: "settings.sidebar.features")) {
                    ForEach(featureIDs, id: \.self) { id in
                        let feature = registry.feature(id)!
                        SidebarRow(title: feature.title, icon: feature.icon, tint: feature.tint,
                                   isOff: !registry.isEnabled(id))
                            .tag(SettingsTab.feature(id))
                    }
                }

                Section {
                    SidebarRow(title: String(localized: "settings.tab.about"), icon: "info", tint: .gray)
                        .tag(SettingsTab.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(title)
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    private var featureIDs: [FeatureID] { registry.features.map { FeatureRegistry.id(of: $0) } }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selectedTab {
        case .general:
            GeneralSettingsView(launchAtLogin: context.launchAtLogin, hud: context.hud,
                                settings: context.settings, preferences: context.preferences,
                                hotkeys: context.hotkeys)
        case .feature(let id) where registry.feature(id) != nil:
            FeatureSettingsView(featureID: id, registry: registry, hotkeys: context.hotkeys,
                                permissions: context.permissions)
                .id(id)  // fresh state per feature page
        case .feature:
            EmptyView()
        case .about:
            AboutView(storage: context.storage, registry: registry, hotkeys: context.hotkeys) { id in
                navigation.selectedTab = .feature(id)
            }
        }
    }

    private var title: String {
        switch navigation.selectedTab {
        case .general: String(localized: "settings.tab.general")
        case .feature(let id): registry.feature(id)?.title ?? ""
        case .about: String(localized: "settings.tab.about")
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let icon: String
    let tint: Color
    var isOff = false

    var body: some View {
        HStack(spacing: 8) {
            SettingsIcon(symbol: icon, tint: isOff ? .gray : tint)
            Text(title)
                .foregroundStyle(isOff ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if isOff {
                Text(String(localized: "settings.feature.off"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct GeneralSettingsView: View {
    let launchAtLogin: LaunchAtLogin
    @Bindable var hud: HUDService
    let settings: SettingsStore
    @Bindable var preferences: AppPreferences
    let hotkeys: HotkeyService

    var body: some View {
        Form {
            Section {
                SettingsHeader(icon: "gearshape", tint: .gray, title: String(localized: "settings.tab.general"),
                               summary: String(localized: "settings.general.summary"))
            }
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
                Button(String(localized: "settings.general.resetShortcuts")) { hotkeys.resetAll() }
            } header: {
                Text(String(localized: "settings.general.shortcuts"))
            } footer: {
                Text(String(localized: "settings.general.shortcutsFooter")).foregroundStyle(.secondary)
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
    let registry: FeatureRegistry
    let hotkeys: HotkeyService
    let openFeature: (FeatureID) -> Void

    var body: some View {
        Form {
            Section {
                SettingsHeader(icon: "info", tint: .gray, title: String(localized: "settings.tab.about"),
                               summary: String(localized: "settings.about.summary"))
            }
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppInfo.name).font(.title2.bold())
                        Text(String(format: String(localized: "settings.about.version"), AppInfo.version))
                            .foregroundStyle(.secondary)
                        Text(String(localized: "settings.about.tagline"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                Button(String(localized: "settings.about.openData")) {
                    try? FileManager.default.createDirectory(at: storage.baseURL, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(storage.baseURL)
                }
            }
            Section {
                ForEach(registry.features.map { FeatureRegistry.id(of: $0) }, id: \.self) { id in
                    FeatureOverviewRow(feature: registry.feature(id)!, isEnabled: registry.isEnabled(id),
                                       hotkeys: hotkeys) { openFeature(id) }
                }
            } header: {
                Text(String(localized: "settings.sidebar.features"))
            } footer: {
                Text(String(localized: "settings.about.featuresFooter")).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// A feature in the About overview: what it does and how to call it. Click opens its page.
private struct FeatureOverviewRow: View {
    let feature: any Feature
    let isEnabled: Bool
    let hotkeys: HotkeyService
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                SettingsIcon(symbol: feature.icon, tint: isEnabled ? feature.tint : .gray, size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(feature.title).font(.headline)
                        if !isEnabled {
                            Text(String(localized: "settings.feature.off"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !feature.summary.isEmpty {
                        Text(feature.summary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(feature.actions.filter { !$0.isInternal }, id: \.id) { action in
                        HStack {
                            Text(action.title)
                            Spacer()
                            Text(hotkeys.shortcut(for: action.id)?.description
                                 ?? String(localized: "settings.about.noShortcut"))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .help(String(localized: "settings.about.openFeature"))
    }
}
