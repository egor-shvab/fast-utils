import AppKit
import SwiftUI

struct SettingsView: View {
    let registry: FeatureRegistry
    let context: AppContext
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            GeneralSettingsView(registry: registry, launchAtLogin: context.launchAtLogin, hud: context.hud)
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

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "settings.general.launchAtLogin"), isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
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
        }
        .formStyle(.grouped)
    }
}

/// Temporary content for tabs implemented in later stages.
public struct PlaceholderPane: View {
    let text: String

    public init(text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
