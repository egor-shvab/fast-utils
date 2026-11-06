import Carbon.HIToolbox
import Core
import Observation
import OSLog
import SwiftUI

/// Layout and case: fixes text typed in the wrong keyboard layout and toggles UPPER/lower case
/// in the selection or, with nothing selected, in the word before the caret.
public final class TextFeature: Feature {
    public static let id: FeatureID = "text"

    private let context: AppContext
    private let log: Logger
    let settings: TextSettings

    public init(context: AppContext) {
        self.context = context
        log = context.logger(Self.id.rawValue)
        settings = TextSettings(store: context.settings.scoped(Self.id))
    }

    public var title: String { String(localized: "feature.text.title") }
    public var icon: String { "textformat" }
    public var summary: String { String(localized: "feature.text.summary") }
    public var tint: Color { .teal }
    public var requiredPermissions: Set<Permission> { [.accessibility] }

    public var actions: [FeatureAction] {
        [
            FeatureAction(
                id: "text.fixLayout",
                title: String(localized: "text.action.fixLayout"),
                defaultShortcut: Shortcut(kVK_ANSI_R, [.option, .command])
            ) { [weak self] _ in
                await self?.fixLayout()
                return .none
            },
            FeatureAction(
                id: "text.toggleCase",
                title: String(localized: "text.action.toggleCase"),
                defaultShortcut: Shortcut(kVK_ANSI_U, [.option, .command])
            ) { [weak self] _ in
                await self?.toggleCase()
                return .none
            },
        ]
    }

    public var settingsView: AnyView? { AnyView(TextSettingsView(settings: settings)) }

    // MARK: Actions

    func fixLayout() async {
        var target: KeyboardLayoutMap.Language?
        let outcome = await context.paste.replaceSelectionOrLastWord { text in
            let converted = KeyboardLayoutMap.convert(text)
            target = converted.target
            return converted.text
        }
        report(outcome)
        if outcome == .replaced, settings.switchLayout, let target {
            InputSourceSwitcher.select(language: target.rawValue)
        }
        log.notice("Fix layout: \(String(describing: outcome), privacy: .public)")
    }

    func toggleCase() async {
        let outcome = await context.paste.replaceSelectionOrLastWord(CaseToggle.apply)
        report(outcome)
        log.notice("Toggle case: \(String(describing: outcome), privacy: .public)")
    }

    private func report(_ outcome: PasteService.ReplaceOutcome) {
        switch outcome {
        case .replaced:
            break
        case .nothingToReplace:
            context.hud.show(String(localized: "text.hud.nothing"), icon: "textformat", style: .info)
        case .missingPermission:
            context.hud.show(String(localized: "text.hud.noPermission"), style: .error)
            context.permissions.request(.accessibility)
        }
    }
}

/// Preferences, persisted under `text.*`.
@MainActor
@Observable
final class TextSettings {
    /// After fixing the layout, switch the system keyboard layout to the result's language.
    var switchLayout: Bool { didSet { store.set(switchLayout, for: "switchLayout") } }

    @ObservationIgnored private let store: ScopedSettings

    init(store: ScopedSettings) {
        self.store = store
        switchLayout = store.value("switchLayout", default: true)
    }
}

struct TextSettingsView: View {
    @Bindable var settings: TextSettings

    var body: some View {
        Group {
            Section {
                Toggle(String(localized: "text.settings.switchLayout"), isOn: $settings.switchLayout)
            } footer: {
                Text(String(localized: "text.settings.footer"))
            }
        }
    }
}
