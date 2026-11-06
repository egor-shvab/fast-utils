import SwiftUI

/// A feature's Settings tab. Everything about the feature lives here: the on/off switch,
/// its shortcuts, the permissions it needs, then the feature's own sections
/// (`Feature.settingsView`). While the feature is off, everything below the switch is dimmed.
struct FeatureSettingsView: View {
    let featureID: FeatureID
    let registry: FeatureRegistry
    let hotkeys: HotkeyService
    let permissions: PermissionsService

    var body: some View {
        let feature = registry.feature(featureID)!
        let enabled = registry.isEnabled(featureID)
        let actionIDs = feature.actions.filter { !$0.isInternal }.map(\.id)
        let required = Permission.allCases.filter(feature.requiredPermissions.contains)

        Form {
            Section {
                SettingsHeader(icon: feature.icon, tint: feature.tint, title: feature.title, summary: feature.summary) {
                    Toggle(String(localized: "settings.feature.enabled"), isOn: Binding(
                        get: { registry.isEnabled(featureID) },
                        set: { newValue in Task { await registry.setEnabled(newValue, for: featureID) } }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(String(localized: "settings.feature.enabledFooter"))
                    .accessibilityLabel(String(localized: "settings.feature.enabled"))
                }
            } footer: {
                if !enabled {
                    Text(String(localized: "settings.feature.enabledFooter")).foregroundStyle(.secondary)
                }
            }

            Group {
                if !actionIDs.isEmpty {
                    Section {
                        ForEach(actionIDs, id: \.self) { actionID in
                            ShortcutRecorder(title: hotkeys.title(for: actionID) ?? actionID.rawValue,
                                             id: actionID, hotkeys: hotkeys)
                        }
                        Button(String(localized: "settings.feature.resetShortcuts")) { hotkeys.reset(actionIDs) }
                    } header: {
                        Text(String(localized: "settings.feature.shortcuts"))
                    } footer: {
                        Text(String(localized: "settings.feature.shortcutsFooter")).foregroundStyle(.secondary)
                    }
                }

                if !required.isEmpty {
                    Section {
                        PermissionsList(permissions: required, service: permissions)
                    } header: {
                        Text(String(localized: "settings.feature.permissions"))
                    }
                }

                if let own = feature.settingsView {
                    own
                }
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
    }
}
