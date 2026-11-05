import Carbon.HIToolbox
import Testing
@testable import Core

@MainActor
final class HotkeyFeature: Feature {
    static let id: FeatureID = "hk"
    static var runs = 0
    init(context: AppContext) {}
    var title: String { "HK" }
    var icon: String { "keyboard" }
    var actions: [FeatureAction] {
        [
            FeatureAction(id: "hk.one", title: "One", defaultShortcut: Shortcut(kVK_ANSI_2, [.shift, .command])) { _ in
                HotkeyFeature.runs += 1
                return .none
            },
            FeatureAction(id: "hk.two", title: "Two", defaultShortcut: Shortcut(kVK_ANSI_T, [.option, .command])) { _ in .none },
            FeatureAction(id: "hk.three", title: "Three") { _ in .none },
        ]
    }
}

@MainActor
struct HotkeyServiceTests {
    let fake = FakeHotkeyRegistrar()
    let context: AppContext
    let registry: FeatureRegistry
    var hotkeys: HotkeyService { context.hotkeys }

    let cmdShift2 = Shortcut(kVK_ANSI_2, [.shift, .command])
    let ctrlOptK = Shortcut(kVK_ANSI_K, [.control, .option])

    init() {
        context = AppContext.testing(hotkeys: fake)
        registry = FeatureRegistry(context: context, types: [HotkeyFeature.self])
    }

    @Test func defaultsAreRegisteredWhenFeatureStarts() async {
        #expect(fake.registered.isEmpty)
        await registry.startEnabledFeatures()

        #expect(fake.registered["hk.one"] == cmdShift2)
        #expect(fake.registered["hk.two"] == Shortcut(kVK_ANSI_T, [.option, .command]))
        #expect(fake.registered["hk.three"] == nil)
    }

    @Test func pressingHotkeyRunsAction() async {
        await registry.startEnabledFeatures()
        HotkeyFeature.runs = 0

        fake.press("hk.one")
        for _ in 0..<10 where HotkeyFeature.runs == 0 { await Task.yield() }

        #expect(HotkeyFeature.runs == 1)
    }

    @Test func disablingFeatureReleasesHotkeys() async {
        await registry.startEnabledFeatures()
        await registry.setEnabled(false, for: "hk")

        #expect(fake.registered.isEmpty)
        // Still known, so other actions cannot take it.
        #expect(hotkeys.shortcut(for: "hk.one") == cmdShift2)
    }

    @Test func changeIsPersistedAndReregistered() async {
        await registry.startEnabledFeatures()
        #expect(hotkeys.setShortcut(ctrlOptK, for: "hk.three"))
        #expect(fake.registered["hk.three"] == ctrlOptK)

        // Fresh service over the same settings, like an app restart.
        let restarted = HotkeyService(
            actions: ActionRegistry(), settings: context.settings.scoped("hotkeys"),
            registrar: FakeHotkeyRegistrar(), log: context.logger("test")
        )
        restarted.declare(HotkeyFeature(context: context).actions)
        #expect(restarted.shortcut(for: "hk.three") == ctrlOptK)
    }

    @Test func clearedShortcutStaysClearedAfterRestart() async {
        await registry.startEnabledFeatures()
        hotkeys.setShortcut(nil, for: "hk.one")
        #expect(fake.registered["hk.one"] == nil)

        let restarted = HotkeyService(
            actions: ActionRegistry(), settings: context.settings.scoped("hotkeys"),
            registrar: FakeHotkeyRegistrar(), log: context.logger("test")
        )
        restarted.declare(HotkeyFeature(context: context).actions)
        #expect(restarted.shortcut(for: "hk.one") == nil)
    }

    @Test func duplicateIsBlocked() async {
        await registry.startEnabledFeatures()

        #expect(hotkeys.check(cmdShift2, for: "hk.three") == .blocked(
            String(format: String(localized: "shortcut.check.duplicate"), "One")
        ))
        #expect(!hotkeys.setShortcut(cmdShift2, for: "hk.three"))
        #expect(hotkeys.shortcut(for: "hk.three") == nil)
        // Re-assigning an action its own shortcut is not a duplicate.
        if case .blocked = hotkeys.check(cmdShift2, for: "hk.one") { Issue.record("own shortcut blocked") }
    }

    @Test func reservedShortcutIsBlocked() {
        let copy = Shortcut(kVK_ANSI_C, .command)
        guard case .blocked = hotkeys.check(copy, for: "hk.three") else {
            Issue.record("⌘C must be blocked"); return
        }
    }

    @Test func knownShortcutWarns() {
        let reopenTab = Shortcut(kVK_ANSI_T, [.shift, .command])
        guard case .warning = ShortcutRules.check(reopenTab, conflictingTitle: nil, systemShortcuts: []) else {
            Issue.record("⇧⌘T must warn"); return
        }
        #expect(ShortcutRules.check(ctrlOptK, conflictingTitle: nil, systemShortcuts: []) == .ok)
        #expect(ShortcutRules.check(ctrlOptK, conflictingTitle: nil, systemShortcuts: [ctrlOptK])
            == .warning(String(localized: "shortcut.check.system")))
    }

    @Test func pauseReleasesAndRestores() async {
        await registry.startEnabledFeatures()
        hotkeys.isPaused = true
        #expect(fake.registered.isEmpty)
        hotkeys.isPaused = false
        #expect(fake.registered.count == 2)
    }

    @Test func resetRestoresDefault() async {
        await registry.startEnabledFeatures()
        hotkeys.setShortcut(ctrlOptK, for: "hk.one")
        hotkeys.reset(["hk.one"])
        #expect(hotkeys.shortcut(for: "hk.one") == cmdShift2)
        #expect(fake.registered["hk.one"] == cmdShift2)
    }

    @Test func resetAllRestoresSwappedDefaults() async {
        await registry.startEnabledFeatures()
        let optCmdT = Shortcut(kVK_ANSI_T, [.option, .command])
        // Swap: one → ⌃⌥K, two → ⇧⌘2, one → ⌥⌘T.
        hotkeys.setShortcut(ctrlOptK, for: "hk.one")
        hotkeys.setShortcut(cmdShift2, for: "hk.two")
        hotkeys.setShortcut(optCmdT, for: "hk.one")

        hotkeys.resetAll()

        #expect(hotkeys.shortcut(for: "hk.one") == cmdShift2)
        #expect(hotkeys.shortcut(for: "hk.two") == optCmdT)
    }
}
