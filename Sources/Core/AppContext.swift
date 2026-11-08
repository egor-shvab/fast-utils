import AppKit
import Foundation
import OSLog

/// Shared services handed to every feature in `init(context:)`. The only way features get
/// Core services — no singletons. New shared services are added here.
@MainActor
public final class AppContext {
    public let settings: SettingsStore
    public let secrets: any SecretStore
    public let storage: StorageService
    public let events: EventBus
    public let actions: ActionRegistry
    public let hotkeys: HotkeyService
    public let permissions: PermissionsService
    public let hud: HUDService
    public let panels: PanelService
    public let launchAtLogin: LaunchAtLogin
    public let pasteboard: PasteboardService
    public let paste: PasteService
    /// Snapshots of every screen (without FastUtils' windows), shared by the screen features.
    public let screenCapture: ScreenCaptureService
    public let areaSelection: AreaSelectionService
    public let colorPicker: ColorPickerService
    public let statusIndicator = StatusIndicator()
    public let preferences: AppPreferences

    public init(
        settings: SettingsStore = SettingsStore(),
        secrets: any SecretStore = KeychainSecretStore(),
        storage: StorageService = StorageService(),
        events: EventBus = EventBus(),
        actions: ActionRegistry = ActionRegistry(),
        hotkeyRegistrar: any HotkeyRegistrar = CarbonHotkeyRegistrar(),
        permissionChecker: any PermissionChecker = SystemPermissionChecker(),
        pasteboard: NSPasteboard = .general,
        keystrokes: any KeystrokeSender = SystemKeystrokeSender()
    ) {
        self.settings = settings
        self.secrets = secrets
        self.storage = storage
        self.events = events
        self.actions = actions
        self.hotkeys = HotkeyService(
            actions: actions,
            settings: settings.scoped("hotkeys"),
            registrar: hotkeyRegistrar,
            log: Logger(subsystem: AppInfo.bundleIdentifier, category: "hotkeys")
        )
        self.permissions = PermissionsService(checker: permissionChecker)
        self.preferences = AppPreferences(settings: settings.app)
        self.hud = HUDService(settings: settings.app)
        self.panels = PanelService()
        self.launchAtLogin = LaunchAtLogin()
        self.pasteboard = PasteboardService(pasteboard: pasteboard, events: events)
        self.paste = PasteService(pasteboard: self.pasteboard, keystrokes: keystrokes)
        self.screenCapture = ScreenCaptureService()
        self.areaSelection = AreaSelectionService(capture: screenCapture)
        self.colorPicker = ColorPickerService(capture: screenCapture)
    }

    /// Logger for a category, e.g. `context.logger("ocr")`.
    /// Never log clipboard contents, recognized/translated text or secrets.
    public func logger(_ category: String) -> Logger {
        Logger(subsystem: AppInfo.bundleIdentifier, category: category)
    }

    /// Isolated context for tests: throwaway UserDefaults suite, in-memory secrets, temp storage,
    /// fake hot keys and permissions (nothing touches the system).
    public static func testing(
        hotkeys: FakeHotkeyRegistrar = FakeHotkeyRegistrar(),
        permissions: FakePermissionChecker = FakePermissionChecker(),
        pasteboard: NSPasteboard? = nil,
        keystrokes: FakeKeystrokeSender = FakeKeystrokeSender()
    ) -> AppContext {
        let suite = "FastUtilsTests.\(UUID().uuidString)"
        let context = AppContext(
            settings: SettingsStore(defaults: UserDefaults(suiteName: suite)!),
            secrets: InMemorySecretStore(),
            storage: StorageService(
                baseURL: FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
            ),
            hotkeyRegistrar: hotkeys,
            permissionChecker: permissions,
            pasteboard: pasteboard ?? NSPasteboard(name: NSPasteboard.Name(suite)),
            keystrokes: keystrokes
        )
        context.paste.focusDelay = .zero
        context.paste.restoreDelay = .zero
        context.paste.selectionTimeout = .milliseconds(60)
        return context
    }
}
