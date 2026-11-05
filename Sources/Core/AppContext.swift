import Foundation
import OSLog

/// Shared services handed to every feature in `init(context:)`. The only way features get
/// Core services — no singletons. New services (hotkeys, HUD, panels, pasteboard…) are added
/// here in later stages.
@MainActor
public final class AppContext {
    public let settings: SettingsStore
    public let secrets: any SecretStore
    public let storage: StorageService
    public let events: EventBus
    public let actions: ActionRegistry

    public init(
        settings: SettingsStore = SettingsStore(),
        secrets: any SecretStore = KeychainSecretStore(),
        storage: StorageService = StorageService(),
        events: EventBus = EventBus(),
        actions: ActionRegistry = ActionRegistry()
    ) {
        self.settings = settings
        self.secrets = secrets
        self.storage = storage
        self.events = events
        self.actions = actions
    }

    /// Logger for a category, e.g. `context.logger("ocr")`.
    /// Never log clipboard contents, recognized/translated text or secrets.
    public func logger(_ category: String) -> Logger {
        Logger(subsystem: AppInfo.bundleIdentifier, category: category)
    }

    /// Isolated context for tests: throwaway UserDefaults suite, in-memory secrets, temp storage.
    public static func testing() -> AppContext {
        let suite = "FastUtilsTests.\(UUID().uuidString)"
        return AppContext(
            settings: SettingsStore(defaults: UserDefaults(suiteName: suite)!),
            secrets: InMemorySecretStore(),
            storage: StorageService(
                baseURL: FileManager.default.temporaryDirectory.appending(path: suite, directoryHint: .isDirectory)
            )
        )
    }
}
