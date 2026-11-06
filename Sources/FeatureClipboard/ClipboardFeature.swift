import AppKit
import ImageIO
import Carbon.HIToolbox
import Core
import OSLog
import SwiftUI

/// Clipboard history: remembers everything copied, shows it in a searchable window
/// and pastes the chosen item back.
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
    public var summary: String { String(localized: "feature.clipboard.summary") }
    public var tint: Color { .orange }
    public var requiredPermissions: Set<Permission> { [.accessibility, .pasteboard] }

    public var actions: [FeatureAction] {
        [
            FeatureAction(
                id: "clipboard.showHistory",
                title: String(localized: "clipboard.action.showHistory"),
                defaultShortcut: Shortcut(kVK_ANSI_V, [.option, .command])
            ) { [weak self] _ in
                await self?.toggleHistory()
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
        prewarmTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await self?.prewarmHistoryWindow()
        }
    }

    public func stop() async {
        context.pasteboard.stopMonitoring()
        context.pasteboard.shouldReadContents = nil
        eventsTask?.cancel()
        eventsTask = nil
        prewarmTask?.cancel()
        prewarmTask = nil
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

    // MARK: History window

    static let panelID = "clipboard.history"
    private var keyMonitor: Any?
    private var prewarmTask: Task<Void, Never>?

    /// The first history window after launch took 190–300 ms (cold SwiftUI, SQLite and
    /// thumbnail caches), later ones ~60 ms (target: under 150 ms). Rendering the list once
    /// off-screen shortly after launch moves that cost out of the first ⌥⌘V.
    private func prewarmHistoryWindow() async {
        guard let store, !Task.isCancelled else { return }
        let started = ContinuousClock.now
        let model = HistoryViewModel(store: store, limit: settings.maxItems)
        await model.reload()
        let hosting = NSHostingView(rootView: HistoryView(model: model))
        hosting.frame = CGRect(x: 0, y: 0, width: 440, height: 540)
        hosting.layoutSubtreeIfNeeded()
        _ = hosting.fittingSize
        log.notice("History window prewarmed in \((ContinuousClock.now - started).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
    }

    func toggleHistory() async {
        if context.panels.isPresented(Self.panelID) {
            context.panels.close(Self.panelID)
            return
        }
        guard let store else { return }
        let started = ContinuousClock.now
        // Remember where the user was: the paste goes there.
        let targetApp = NSWorkspace.shared.frontmostApplication
        let model = HistoryViewModel(store: store, limit: settings.maxItems)
        await model.reload()  // so the very first frame already shows the list

        model.onPaste = { [weak self] item, plain in
            Task { await self?.paste(item, plainText: plain, into: targetApp) }
        }
        model.onCopy = { [weak self] item in
            Task { await self?.copy(item) }
        }
        model.onClose = { [weak self] in self?.context.panels.close(Self.panelID) }
        model.previewOnSelect = settings.previewOnSelect
        model.contentActions = { [weak self] item in self?.contentActions(for: item) ?? [] }
        model.onRunAction = { [weak self] item, action in
            Task { await self?.run(action, on: item) }
        }

        let handle = context.panels.present(
            id: Self.panelID, size: CGSize(width: settings.previewOnSelect ? 820 : 440, height: 540), placement: placement(),
            onClose: { [weak self] in self?.removeKeyMonitor() }
        ) { _ in
            HistoryView(model: model)
        }
        installKeyMonitor(for: handle.window, model: model)
        log.notice("History window opened in \((ContinuousClock.now - started).formatted(.units(allowed: [.milliseconds])), privacy: .public)")
    }

    /// Actions of other features that can work on this item.
    func contentActions(for item: ClipItem) -> [FeatureAction] {
        let kind: ActionInputKind? = switch item.kind {
        case .text, .link: .text
        case .image: .image
        case .files: nil
        }
        guard let kind else { return [] }
        return context.actions.actions(accepting: kind, excluding: Self.id)
    }

    /// Runs another feature's action on an item; a text result is copied.
    func run(_ action: FeatureAction, on item: ClipItem) async {
        context.panels.close(Self.panelID)
        let full = (try? await store?.item(item.id)) ?? item
        let input: ActionInput
        switch full.kind {
        case .text, .link:
            input = .text(full.text ?? "")
        case .image:
            guard let url = full.imageURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                context.hud.show(String(localized: "clipboard.hud.imageMissing"), style: .error)
                return
            }
            input = .image(image)
        case .files:
            return
        }
        do {
            let output = try await context.actions.perform(action.id, input: input)
            if case .text(let text) = output {
                if text.isEmpty {
                    context.hud.show(String(localized: "clipboard.hud.noResult"), style: .info)
                } else {
                    context.pasteboard.writeText(text)
                    context.hud.show(String(localized: "clipboard.hud.copied"))
                }
            }
        } catch {
            log.error("Action \(action.id.rawValue, privacy: .public) on history item failed: \(String(describing: error), privacy: .public)")
            context.hud.show(String(localized: "clipboard.hud.actionFailed"), style: .error)
        }
    }

    private func placement() -> PanelService.Placement {
        switch settings.windowPosition {
        case .mouse: .nearCursor
        case .center: .center
        case .textCursor: TextCaret.rect().map { .near(CGPoint(x: $0.minX, y: $0.minY)) } ?? .nearCursor
        }
    }

    /// Arrows, Enter, ⌘1…⌘9 and the rest reach the window whatever has focus; plain typing
    /// goes on to the search field.
    private func installKeyMonitor(for window: NSWindow?, model: HistoryViewModel) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window, weak model] event in
            guard let window, let model, event.window === window else { return event }
            let command = HistoryCommand.from(
                keyCode: Int(event.keyCode), modifiers: event.modifierFlags, queryIsEmpty: model.query.isEmpty
            )
            return model.handle(command) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func paste(_ item: ClipItem, plainText: Bool, into targetApp: NSRunningApplication?) async {
        context.panels.close(Self.panelID)
        guard let snapshot = await snapshot(for: item) else { return }
        let outcome = await context.paste.paste(
            snapshot, plainText: plainText, into: targetApp,
            autoPaste: settings.autoPaste, restorePrevious: settings.restorePrevious
        )
        switch outcome {
        case .pasted: break
        case .copied(let missingPermission):
            context.hud.show(String(localized: missingPermission ? "clipboard.hud.copiedNoPermission" : "clipboard.hud.copied"))
        }
    }

    func copy(_ item: ClipItem) async {
        context.panels.close(Self.panelID)
        guard let snapshot = await snapshot(for: item) else { return }
        context.pasteboard.write(snapshot)
        context.hud.show(String(localized: "clipboard.hud.copied"))
    }

    /// Everything needed to put the item back on the clipboard (full text, formats, image, files).
    func snapshot(for item: ClipItem) async -> PasteboardSnapshot? {
        let full = (try? await store?.item(item.id)) ?? item
        switch full.kind {
        case .text, .link:
            return PasteboardSnapshot(string: full.text, rtf: full.rtf, html: full.html)
        case .image:
            guard let url = full.imageURL, let data = try? Data(contentsOf: url) else {
                context.hud.show(String(localized: "clipboard.hud.imageMissing"), style: .error)
                return nil
            }
            return PasteboardSnapshot(image: data)
        case .files:
            let existing = full.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !existing.isEmpty else {
                context.hud.show(String(localized: "clipboard.window.fileMissing"), style: .error)
                return nil
            }
            return PasteboardSnapshot(fileURLs: existing)
        }
    }
}

extension HistoryStore.AddResult {
    var isBump: Bool { if case .bumped = self { true } else { false } }
}
