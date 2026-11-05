import Carbon.HIToolbox
import Core
import OSLog
import SwiftUI

/// Stub until its stage in ROADMAP.md: one action that shows a placeholder HUD or panel.
public final class ClipboardFeature: Feature {
    public static let id: FeatureID = "clipboard"

    private let context: AppContext
    private let log: Logger

    public init(context: AppContext) {
        self.context = context
        log = context.logger(Self.id.rawValue)
    }

    public var title: String { String(localized: "feature.clipboard.title") }
    public var icon: String { "doc.on.clipboard" }
    public var requiredPermissions: Set<Permission> { [.accessibility, .pasteboard] }

    public var actions: [FeatureAction] {
        [
            FeatureAction(
                id: "clipboard.showHistory",
                title: String(localized: "clipboard.action.showHistory"),
                defaultShortcut: Shortcut(kVK_ANSI_V, [.option, .command])
            ) { [weak self] _ in
                guard let self else { return .none }
                log.notice("Stub action clipboard.showHistory")
                context.panels.toggle(id: "clipboard", size: CGSize(width: 420, height: 260)) { handle in
                    StubPanelView(
                        title: title, text: String(localized: "stub.clipboard.text"), showsSearch: true, handle: handle
                    )
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
