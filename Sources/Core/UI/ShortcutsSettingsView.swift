import SwiftUI

struct ShortcutsSettingsView: View {
    let registry: FeatureRegistry
    let hotkeys: HotkeyService

    var body: some View {
        Form {
            ForEach(enabledFeatureIDs, id: \.self) { featureID in
                let feature = registry.feature(featureID)!
                Section {
                    ForEach(feature.actions.filter { !$0.isInternal }.map(\.id), id: \.self) { actionID in
                        LabeledContent(hotkeys.title(for: actionID) ?? actionID.rawValue) {
                            ShortcutRecorder(id: actionID, hotkeys: hotkeys)
                        }
                    }
                } header: {
                    Label(feature.title, systemImage: feature.icon)
                }
            }
            Section {
                Button(String(localized: "shortcut.settings.resetAll")) { hotkeys.resetAll() }
            } footer: {
                Text(String(localized: "shortcut.settings.footer"))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var enabledFeatureIDs: [FeatureID] {
        registry.features.map { FeatureRegistry.id(of: $0) }.filter { registry.isEnabled($0) }
    }
}
