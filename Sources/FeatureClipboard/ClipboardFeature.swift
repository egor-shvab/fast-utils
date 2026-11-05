import AppKit
import Carbon.HIToolbox
import Core
import OSLog
import SwiftUI

/// Function 3 (TZ.md §7): remembers everything copied. Stage 5 — tracking and storage;
/// the history window arrives in stage 6.
public final class ClipboardFeature: Feature {
    public static let id: FeatureID = "clipboard"

    enum Pause: Equatable {
        case none
        case until(Date)
        case untilRestart
        case indefinitely
    }

    private let context: AppContext
    private let log: Logger
    let settings: ClipboardSettings
    private(set) var store: HistoryStore?
    private var eventsTask: Task<Void, Never>?
    private var pauseTimer: Timer?
    private var temporaryPause: Pause = .none

    public init(context: AppContext) {
        self.context = context
        log = context.logger(Self.id.rawValue)
        settings = ClipboardSettings(store: context.settings.scoped(Self.id))
        settings.onLimitsChanged = { [weak self] in Task { await self?.applyLimits() } }
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
                await self?.showHistoryStub()
                return .none
            },
            FeatureAction(id: "clipboard.togglePause", title: String(localized: "clipboard.action.togglePause")) { [weak self] _ in
                guard let self else { return .none }
                if pause != .none { resume() } else { setPause(.indefinitely) }
                return .none
            },
        ]
    }

    public var menuItems: [MenuItemDescriptor] {
        var items = [MenuItemDescriptor(actionID: "clipboard.showHistory", title: String(localized: "clipboard.action.showHistory"))]
        if pause == .none {
            items.append(.submenu(String(localized: "clipboard.menu.pause"), [
                .custom(String(localized: "clipboard.menu.pause5m")) { [weak self] in self?.setPause(.until(Date().addingTimeInterval(5 * 60))) },
                .custom(String(localized: "clipboard.menu.pause1h")) { [weak self] in self?.setPause(.until(Date().addingTimeInterval(60 * 60))) },
                .custom(String(localized: "clipboard.menu.pauseRestart")) { [weak self] in self?.setPause(.untilRestart) },
                .custom(String(localized: "clipboard.menu.pauseForever")) { [weak self] in self?.setPause(.indefinitely) },
            ]))
        } else {
            items.append(.label(pauseDescription))
            items.append(.custom(String(localized: "clipboard.menu.resume")) { [weak self] in self?.resume() })
        }
        return items
    }

    public var settingsView: AnyView? {
        AnyView(ClipboardSettingsView(settings: settings, feature: self))
    }

    // MARK: Lifecycle

    public func start() async {
        do {
            if store == nil {
                store = try HistoryStore(directory: try context.storage.directory(for: Self.id))
            }
        } catch {
            log.error("Cannot open history: \(String(describing: error), privacy: .public)")
            context.hud.show(String(localized: "clipboard.hud.storeFailed"), style: .error)
            return
        }
        context.pasteboard.shouldReadContents = { [weak self] types, source in
            guard let self else { return false }
            return ClipboardFilter.allowsReading(
                types: types, source: source,
                excludedApps: Set(settings.excludedApps), ignoreConcealed: settings.ignoreConcealed
            )
        }
        let stream = context.events.stream(of: ClipboardChanged.self)
        eventsTask = Task { [weak self] in
            for await change in stream {
                await self?.handle(change)
            }
        }
        context.pasteboard.startMonitoring()
        updateIndicator()
        await applyLimits()
    }

    public func stop() async {
        context.pasteboard.stopMonitoring()
        context.pasteboard.shouldReadContents = nil
        eventsTask?.cancel()
        eventsTask = nil
        pauseTimer?.invalidate()
        context.statusIndicator.set(symbol: nil)
    }

    // MARK: Recording

    func handle(_ change: ClipboardChanged) async {
        guard change.recordInHistory, pause == .none, let store else { return }
        let snapshot = change.snapshot
        guard ClipboardFilter.allowsReading(
            types: snapshot.types, source: snapshot.sourceBundleID,
            excludedApps: Set(settings.excludedApps), ignoreConcealed: settings.ignoreConcealed
        ), let content = ClipContentFactory.content(from: snapshot), settings.allows(content.kind)
        else { return }
        if let image = content.image, image.count > settings.maxImageMB * 1_048_576 {
            log.notice("Skipped image of \(image.count) bytes: over the limit")
            return
        }
        do {
            let result = try await store.add(content, sourceBundleID: snapshot.sourceBundleID, sourceName: snapshot.sourceName)
            // Kind and size only — never the content.
            log.debug("History \(result.isBump ? "bumped" : "added", privacy: .public) \(content.kind.rawValue, privacy: .public), \(content.byteSize) bytes")
            if !result.isBump { await applyLimits() }
        } catch {
            log.error("Cannot store clipboard item: \(String(describing: error), privacy: .public)")
        }
    }

    func applyLimits() async {
        guard let store else { return }
        do {
            let removed = try await store.prune(maxCount: settings.maxItems, maxAge: settings.maxAge)
            if removed > 0 { log.debug("Pruned \(removed) history items") }
        } catch {
            log.error("Prune failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Pause

    var pause: Pause {
        if settings.pausedIndefinitely { return .indefinitely }
        if case .until(let date) = temporaryPause, date <= Date() { return .none }
        return temporaryPause
    }

    func setPause(_ newPause: Pause) {
        pauseTimer?.invalidate()
        settings.pausedIndefinitely = newPause == .indefinitely
        temporaryPause = newPause == .indefinitely ? .none : newPause
        if case .until(let date) = newPause {
            let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            }
            RunLoop.main.add(timer, forMode: .common)
            pauseTimer = timer
        }
        updateIndicator()
        log.notice("History recording \(newPause == .none ? "resumed" : "paused", privacy: .public)")
        if newPause != .none {
            context.hud.show(pauseDescription, icon: "pause.circle.fill", style: .info)
        }
    }

    func resume() {
        let wasPaused = pause != .none
        setPause(.none)
        if wasPaused { context.hud.show(String(localized: "clipboard.hud.resumed"), icon: "play.circle.fill", style: .info) }
    }

    private var pauseDescription: String {
        switch pause {
        case .none: ""
        case .until(let date):
            String(format: String(localized: "clipboard.pause.until"), date.formatted(date: .omitted, time: .shortened))
        case .untilRestart: String(localized: "clipboard.pause.untilRestart")
        case .indefinitely: String(localized: "clipboard.pause.indefinitely")
        }
    }

    private func updateIndicator() {
        if pause == .none {
            context.statusIndicator.set(symbol: nil)
        } else {
            context.statusIndicator.set(symbol: "pause.circle", tooltip: pauseDescription)
        }
    }

    // MARK: Stage 6 placeholder

    private func showHistoryStub() async {
        let count = (try? await store?.count()) ?? 0
        let text = String(format: String(localized: "stub.clipboard.count"), count)
        context.panels.toggle(id: "clipboard", size: CGSize(width: 420, height: 260)) { handle in
            StubPanelView(title: title, text: text, showsSearch: true, handle: handle)
        }
    }
}

extension HistoryStore.AddResult {
    var isBump: Bool { if case .bumped = self { true } else { false } }
}
