import Core
import Foundation
import Observation

/// Clipboard history preferences, persisted under `clipboard.*`.
@MainActor
@Observable
final class ClipboardSettings {
    static let maxItemsOptions = [100, 200, 500, 1_000, 5_000]
    /// Days; 0 = keep forever.
    static let maxAgeOptions = [0, 1, 7, 30, 90]
    static let maxImageMBOptions = [5, 10, 20, 50]

    var maxItems: Int { didSet { store.set(maxItems, for: "maxItems"); onLimitsChanged?() } }
    var maxAgeDays: Int { didSet { store.set(maxAgeDays, for: "maxAgeDays"); onLimitsChanged?() } }
    var maxImageMB: Int { didSet { store.set(maxImageMB, for: "maxImageMB") } }
    var storeText: Bool { didSet { store.set(storeText, for: "storeText") } }
    var storeImages: Bool { didSet { store.set(storeImages, for: "storeImages") } }
    var storeFiles: Bool { didSet { store.set(storeFiles, for: "storeFiles") } }
    var ignoreConcealed: Bool { didSet { store.set(ignoreConcealed, for: "ignoreConcealed") } }
    var excludedApps: [String] { didSet { store.set(excludedApps, for: "excludedApps") } }
    var pausedIndefinitely: Bool { didSet { store.set(pausedIndefinitely, for: "pausedIndefinitely") } }
    var windowPosition: WindowPosition { didSet { store.set(windowPosition.rawValue, for: "windowPosition") } }
    /// `false` = "copy only, don't paste".
    var autoPaste: Bool { didSet { store.set(autoPaste, for: "autoPaste") } }
    var restorePrevious: Bool { didSet { store.set(restorePrevious, for: "restorePrevious") } }
    /// Show the selected item's full content next to the list (otherwise: Space / ⌘Y).
    var previewOnSelect: Bool { didSet { store.set(previewOnSelect, for: "previewOnSelect") } }

    enum WindowPosition: String, CaseIterable, Sendable { case mouse, center, textCursor }

    @ObservationIgnored var onLimitsChanged: (() -> Void)?
    @ObservationIgnored private let store: ScopedSettings

    init(store: ScopedSettings) {
        self.store = store
        maxItems = store.value("maxItems", default: 500)
        maxAgeDays = store.value("maxAgeDays", default: 0)
        maxImageMB = store.value("maxImageMB", default: 20)
        storeText = store.value("storeText", default: true)
        storeImages = store.value("storeImages", default: true)
        storeFiles = store.value("storeFiles", default: true)
        ignoreConcealed = store.value("ignoreConcealed", default: true)
        excludedApps = store.value("excludedApps", default: ClipboardFilter.defaultExcludedApps)
        pausedIndefinitely = store.value("pausedIndefinitely", default: false)
        windowPosition = WindowPosition(rawValue: store.value("windowPosition", default: "")) ?? .mouse
        autoPaste = store.value("autoPaste", default: true)
        restorePrevious = store.value("restorePrevious", default: false)
        previewOnSelect = store.value("previewOnSelect", default: false)
    }

    var maxAge: TimeInterval? { maxAgeDays > 0 ? TimeInterval(maxAgeDays) * 86_400 : nil }

    func allows(_ kind: ClipKind) -> Bool {
        switch kind {
        case .text, .link: storeText
        case .image: storeImages
        case .files: storeFiles
        }
    }
}
