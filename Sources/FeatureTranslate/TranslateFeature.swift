import Carbon.HIToolbox
import Core
import OSLog
import SwiftUI

/// Stub until its stage in ROADMAP.md: one action that shows a placeholder HUD or panel.
public final class TranslateFeature: Feature {
    public static let id: FeatureID = "translate"

    private let context: AppContext
    private let log: Logger

    public init(context: AppContext) {
        self.context = context
        log = context.logger(Self.id.rawValue)
    }

    public var title: String { String(localized: "feature.translate.title") }
    public var icon: String { "character.bubble" }
    public var requiredPermissions: Set<Permission> { [.pasteboard] }

    public var actions: [FeatureAction] {
        [
            FeatureAction(
                id: "translate.clipboard",
                title: String(localized: "translate.action.clipboard"),
                defaultShortcut: Shortcut(kVK_ANSI_T, [.option, .command])
            ) { [weak self] _ in
                guard let self else { return .none }
                log.notice("Stub action translate.clipboard")
                context.panels.toggle(id: "translate", size: CGSize(width: 380, height: 200)) { handle in
                    StubPanelView(title: title, text: String(localized: "stub.translate.text"), handle: handle)
                }
                return .none
            },
        ]
    }

    public var settingsView: AnyView? {
        AnyView(PlaceholderPane(text: String(localized: "stub.settings")))
    }

    public func start() async { log.debug("start") }
    public func stop() async { log.debug("stop") }
}
