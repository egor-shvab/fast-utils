import Foundation
import Observation
import OSLog

/// Global keyboard shortcuts for actions.
///
/// Every action of every feature is *declared* at launch, so defaults are known and
/// duplicates are checked even against turned-off features. Only actions of enabled features
/// are *active*: they hold a system hot key. Turning a feature off releases its hot keys.
///
/// Stored per action in settings `hotkeys.<actionID>`: `{keyCode, modifiers}`, or `"none"`
/// when the user cleared it. No stored value means the action's default.
@MainActor
@Observable
public final class HotkeyService {
    /// Effective shortcut of every declared action that has one.
    public private(set) var assignments: [ActionID: Shortcut] = [:]

    /// While `true` (the user is recording a shortcut), all hot keys are released so the
    /// pressed combination reaches the recorder instead of firing an action.
    public var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            for id in active { reregister(id) }
        }
    }

    @ObservationIgnored private let actions: ActionRegistry
    @ObservationIgnored private let settings: ScopedSettings
    @ObservationIgnored private let registrar: any HotkeyRegistrar
    @ObservationIgnored private let log: Logger
    @ObservationIgnored private var titles: [ActionID: String] = [:]
    @ObservationIgnored private var defaults: [ActionID: Shortcut] = [:]
    @ObservationIgnored private var declaredOrder: [ActionID] = []
    @ObservationIgnored private var active: Set<ActionID> = []
    @ObservationIgnored private lazy var systemShortcuts = ShortcutRules.systemShortcuts()

    init(actions: ActionRegistry, settings: ScopedSettings, registrar: any HotkeyRegistrar, log: Logger) {
        self.actions = actions
        self.settings = settings
        self.registrar = registrar
        self.log = log
        registrar.onPress = { [weak self] id in self?.trigger(id) }
    }

    // MARK: Lifecycle (called by FeatureRegistry)

    func declare(_ newActions: [FeatureAction]) {
        for action in newActions where titles[action.id] == nil {
            titles[action.id] = action.title
            defaults[action.id] = action.defaultShortcut
            declaredOrder.append(action.id)
            assignments[action.id] = stored(action.id)
        }
    }

    func activate(_ ids: [ActionID]) {
        for id in ids where titles[id] != nil && !active.contains(id) {
            active.insert(id)
            reregister(id)
        }
    }

    func deactivate(_ ids: [ActionID]) {
        for id in ids where active.contains(id) {
            active.remove(id)
            registrar.unregister(id)
        }
    }

    // MARK: Queries

    public func shortcut(for id: ActionID) -> Shortcut? { assignments[id] }
    public func defaultShortcut(for id: ActionID) -> Shortcut? { defaults[id] }
    public func title(for id: ActionID) -> String? { titles[id] }
    public func isActive(_ id: ActionID) -> Bool { active.contains(id) }

    /// Another declared action that already uses `shortcut`.
    public func conflict(for shortcut: Shortcut, excluding id: ActionID) -> ActionID? {
        declaredOrder.first { $0 != id && assignments[$0] == shortcut }
    }

    public func check(_ shortcut: Shortcut, for id: ActionID) -> ShortcutCheck {
        ShortcutRules.check(
            shortcut,
            conflictingTitle: conflict(for: shortcut, excluding: id).flatMap { titles[$0] },
            systemShortcuts: systemShortcuts
        )
    }

    // MARK: Changes

    /// Assigns (or clears with `nil`) a shortcut. Callers check `check(_:for:)` first;
    /// a blocked shortcut is refused here as well.
    @discardableResult
    public func setShortcut(_ shortcut: Shortcut?, for id: ActionID) -> Bool {
        guard titles[id] != nil else { return false }
        if let shortcut, case .blocked = check(shortcut, for: id) { return false }
        if let shortcut {
            settings.set(["keyCode": shortcut.keyCode, "modifiers": shortcut.modifiers.rawValue], for: id.rawValue)
        } else {
            settings.set("none", for: id.rawValue)
        }
        assignments[id] = shortcut
        reregister(id)
        return true
    }

    /// Restores defaults. A default that now clashes with another action is left empty.
    public func reset(_ ids: [ActionID]) {
        for id in ids where titles[id] != nil {
            settings.remove(id.rawValue)
            let value = defaults[id].flatMap { conflict(for: $0, excluding: id) == nil ? $0 : nil }
            if value == nil, defaults[id] != nil { settings.set("none", for: id.rawValue) }
            assignments[id] = value
            reregister(id)
        }
    }

    public func resetAll() {
        // Clear first so defaults do not clash with not-yet-reset custom assignments.
        for id in declaredOrder { assignments[id] = nil }
        reset(declaredOrder)
    }

    // MARK: Private

    private func stored(_ id: ActionID) -> Shortcut? {
        let raw = settings.rawValue(id.rawValue)
        if let text = raw as? String, text == "none" { return nil }
        if let dict = raw as? [String: Int], let keyCode = dict["keyCode"], let modifiers = dict["modifiers"] {
            return Shortcut(keyCode, Shortcut.Modifiers(rawValue: modifiers))
        }
        return defaults[id]
    }

    private func reregister(_ id: ActionID) {
        registrar.unregister(id)
        guard active.contains(id), !isPaused, let shortcut = assignments[id] else { return }
        if registrar.register(shortcut, for: id) {
            log.notice("Registered \(shortcut.description, privacy: .public) for \(id.rawValue, privacy: .public)")
        } else {
            log.error("System refused hot key \(shortcut.description, privacy: .public) for \(id.rawValue, privacy: .public)")
        }
    }

    private func trigger(_ id: ActionID) {
        guard !isPaused else { return }
        log.debug("Hotkey \(id.rawValue, privacy: .public)")
        let actions = actions
        let log = log
        Task {
            do {
                try await actions.perform(id)
            } catch {
                log.error("Hotkey action \(id.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
