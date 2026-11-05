import Core
import OSLog
import SwiftUI

/// Stub until its stage in ROADMAP.md: one action that shows a "coming soon" alert.
public final class OCRFeature: Feature {
    public static let id: FeatureID = "ocr"

    private let log: Logger

    public init(context: AppContext) {
        log = context.logger(Self.id.rawValue)
    }

    public var title: String { String(localized: "feature.ocr.title") }
    public var icon: String { "text.viewfinder" }
    public var requiredPermissions: Set<Permission> { [.screenRecording] }

    public var actions: [FeatureAction] {
        [
            FeatureAction(id: "ocr.captureText", title: String(localized: "ocr.action.captureText")) { [weak self] _ in
                guard let self else { return .none }
                log.notice("Stub action ocr.captureText")
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
