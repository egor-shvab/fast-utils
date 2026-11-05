import AppKit
import SwiftUI

struct SettingsView: View {
    let registry: FeatureRegistry
    let context: AppContext
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            GeneralSettingsView(registry: registry)
                .tabItem { Label(String(localized: "settings.tab.general"), systemImage: "gearshape") }
                .tag(SettingsTab.general)

            PlaceholderPane(text: String(localized: "settings.placeholder.shortcuts"))
                .tabItem { Label(String(localized: "settings.tab.shortcuts"), systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            ForEach(featureTabs, id: \.id) { tab in
                tab.view
                    .tabItem { Label(tab.title, systemImage: tab.icon) }
                    .tag(SettingsTab.feature(tab.id))
            }

            PlaceholderPane(text: String(localized: "settings.placeholder.permissions"))
                .tabItem { Label(String(localized: "settings.tab.permissions"), systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)

            AboutView(storage: context.storage)
                .tabItem { Label(String(localized: "settings.tab.about"), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 600, height: 420)
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

    var body: some View {
        Form {
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
