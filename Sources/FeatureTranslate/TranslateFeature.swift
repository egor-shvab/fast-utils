import Core
import OSLog
import SwiftUI

/// Stub until its stage in ROADMAP.md: one action that shows a "coming soon" alert.
public final class TranslateFeature: Feature {
    public static let id: FeatureID = "translate"

    private let log: Logger

    public init(context: AppContext) {
        log = context.logger(Self.id.rawValue)
    }

    public var title: String { String(localized: "feature.translate.title") }
    public var icon: String { "character.bubble" }
    public var requiredPermissions: Set<Permission> { [] }

    public var actions: [FeatureAction] {
        [
            FeatureAction(id: "translate.clipboard", title: String(localized: "translate.action.clipboard")) { [weak self] _ in
                guard let self else { return .none }
                log.notice("Stub action translate.clipboard")
                StubAlert.show(feature: title)
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
